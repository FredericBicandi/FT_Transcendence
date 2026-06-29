"use client";

// useHomeController coordinates player identity, Godot iframe messages, match persistence, and dashboard socket state.
// It communicates with Supabase-backed profile models, useDashboardSocket, and the iframe through postMessage.
// Do not casually change message validation, request sequencing, optimistic progress, or post-match exit handling.

import { useCallback, useEffect, useRef, useState } from "react";
import {
  cacheAuthenticatedPlayerProfile,
  clearCachedAuthenticatedPlayerProfile,
  createPlayerProfileSearchParams,
  createOptimisticMatchProgressUpdate,
  deleteAuthenticatedPlayerAccount,
  loadAuthenticatedPlayerProfileDetails,
  loadPlayerProfile,
  saveAuthenticatedMatchResult,
  type MatchProgressUpdate,
  type PlayerProfile,
} from "@/models/player/playerProfile.model";
import { createSupabaseClient } from "@/models/supabase/client.model";
import { useDashboardSocket } from "@/controllers/home/useDashboardSocket";

const EXIT_GAME_MESSAGE_TYPE = "EXIT_GAME";
const MATCH_SAVED_MESSAGE_TYPE = "match_saved";
const POST_MATCH_EXIT_FALLBACK_MS = 10000;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type HomeControllerOptions = {
  initialPlayerProfile: PlayerProfile | null;
  language: string;
  onMatchComplete?: () => void;
};

function isExitGameMessage(value: unknown) {
  return (
    typeof value === "object" &&
    value !== null &&
    "type" in value &&
    value.type === EXIT_GAME_MESSAGE_TYPE
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function isMatchEndExitGameMessage(value: unknown) {
  return isRecord(value) && value.reason === "match_ended";
}

type MatchSavedMessage = {
  deaths: number;
  duration_seconds: number;
  kills: number;
  match_id: string;
  score: number;
  type: typeof MATCH_SAVED_MESSAGE_TYPE;
};

function isMatchSavedMessage(value: unknown): value is MatchSavedMessage {
  // Validate the game iframe packet before saving anything.
  return (
    isRecord(value) &&
    value.type === MATCH_SAVED_MESSAGE_TYPE &&
    typeof value.match_id === "string" &&
    UUID_PATTERN.test(value.match_id) &&
    typeof value.score === "number" &&
    Number.isFinite(value.score) &&
    typeof value.kills === "number" &&
    Number.isFinite(value.kills) &&
    typeof value.deaths === "number" &&
    Number.isFinite(value.deaths) &&
    typeof value.duration_seconds === "number" &&
    Number.isFinite(value.duration_seconds)
  );
}

function createGameUrl(playerProfile: PlayerProfile, language: string) {
  const searchParams = createPlayerProfileSearchParams(playerProfile);
  searchParams.set("language", language);

  // Pass only the fields the Godot game needs to identify this player.
  return `/Game/index.html?${searchParams.toString()}`;
}

export type MatchProgressAnimation = MatchProgressUpdate & {
  id: number;
};

export function useHomeController({
  initialPlayerProfile,
  language,
  onMatchComplete,
}: HomeControllerOptions) {
  const dashboardSocket = useDashboardSocket();
  const gameWindowRef = useRef<Window | null>(null);
  const isMountedRef = useRef(true);
  const matchCompletionPendingRef = useRef(false);
  const playerProfileRef = useRef<PlayerProfile | null>(null);
  const postMatchExitTimeoutRef = useRef<number | null>(null);
  const profileRequestIdRef = useRef(0);
  const profileDetailsRequestIdRef = useRef(0);
  const loadedProfileDetailsKeyRef = useRef<string | null>(null);
  const progressAnimationIdRef = useRef(0);
  const [activeGameUrl, setActiveGameUrl] = useState<string | null>(null);
  const [showGame, setShowGame] = useState(false);
  const [isPlayerProfileLoading, setIsPlayerProfileLoading] = useState(
    initialPlayerProfile === null,
  );
  const [matchProgressAnimation, setMatchProgressAnimation] =
    useState<MatchProgressAnimation | null>(null);
  const [playerProfile, setPlayerProfile] = useState<PlayerProfile | null>(
    initialPlayerProfile,
  );

  const clearMatchProgressAnimation = useCallback(() => {
    setMatchProgressAnimation(null);
  }, []);

  const clearPostMatchExitTimeout = useCallback(() => {
    if (postMatchExitTimeoutRef.current !== null) {
      window.clearTimeout(postMatchExitTimeoutRef.current);
      postMatchExitTimeoutRef.current = null;
    }
  }, []);

  const finishPostMatchFlow = useCallback(() => {
    const currentProfile = playerProfileRef.current;
    const shouldOpenProfile =
      matchCompletionPendingRef.current &&
      currentProfile !== null &&
      !currentProfile.isGuest;
    matchCompletionPendingRef.current = false;
    clearPostMatchExitTimeout();
    setActiveGameUrl(null);
    setShowGame(false);
    if (shouldOpenProfile) {
      // Show saved progress only after a real completed authenticated match.
      onMatchComplete?.();
    }
  }, [clearPostMatchExitTimeout, onMatchComplete]);

  useEffect(() => {
    playerProfileRef.current = playerProfile;
  }, [playerProfile]);

  useEffect(() => {
    if (
      showGame ||
      isPlayerProfileLoading ||
      !playerProfile ||
      playerProfile.isGuest
    ) {
      return;
    }

    const detailsKey = `${playerProfile.playerId}:${playerProfile.level}`;

    // Avoid reloading history for the same profile/level pair.
    if (
      loadedProfileDetailsKeyRef.current === detailsKey ||
      playerProfile.matchLogs.length > 0
    ) {
      return;
    }

    const requestId = profileDetailsRequestIdRef.current + 1;
    profileDetailsRequestIdRef.current = requestId;

    // Later profile refreshes can finish before this details request; ignore stale completions.
    void loadAuthenticatedPlayerProfileDetails({
      level: playerProfile.level,
      playerId: playerProfile.playerId,
    })
      .then((details) => {
        if (
          !isMountedRef.current ||
          profileDetailsRequestIdRef.current !== requestId
        ) {
          return;
        }

        loadedProfileDetailsKeyRef.current = detailsKey;
        setPlayerProfile((currentProfile) => {
          if (
            !currentProfile ||
            currentProfile.isGuest ||
            currentProfile.playerId !== playerProfile.playerId ||
            currentProfile.level !== playerProfile.level
          ) {
            return currentProfile;
          }

          const updatedProfile = {
            ...currentProfile,
            matchLogs: details.matchLogs,
            xpRequiredForNextLevel: details.xpRequiredForNextLevel,
          };

          cacheAuthenticatedPlayerProfile(updatedProfile);
          return updatedProfile;
        });
      })
      .catch(() => {
        // Keep the core profile usable even when history/progress enrichment fails.
      });
  }, [isPlayerProfileLoading, playerProfile, showGame]);

  const refreshPlayerProfile = useCallback(async () => {
    const requestId = profileRequestIdRef.current + 1;
    profileRequestIdRef.current = requestId;
    loadedProfileDetailsKeyRef.current = null;
    // Invalidate any in-flight details request tied to the previous profile snapshot.
    profileDetailsRequestIdRef.current += 1;
    setIsPlayerProfileLoading(true);

    try {
      const profile = await loadPlayerProfile({ preferCache: false });

      if (
        isMountedRef.current &&
        profileRequestIdRef.current === requestId
      ) {
        cacheAuthenticatedPlayerProfile(profile);
        setPlayerProfile(profile);
      }
    } finally {
      if (
        isMountedRef.current &&
        profileRequestIdRef.current === requestId
      ) {
        setIsPlayerProfileLoading(false);
      }
    }
  }, []);

  useEffect(() => {
    isMountedRef.current = true;

    if (initialPlayerProfile) {
      cacheAuthenticatedPlayerProfile(initialPlayerProfile);

      return () => {
        isMountedRef.current = false;
        profileRequestIdRef.current += 1;
        clearPostMatchExitTimeout();
      };
    }

    const requestId = profileRequestIdRef.current + 1;
    profileRequestIdRef.current = requestId;

    async function resolvePlayerProfile() {
      try {
        const profile = await loadPlayerProfile();

        if (
          isMountedRef.current &&
          profileRequestIdRef.current === requestId
        ) {
          cacheAuthenticatedPlayerProfile(profile);
          setPlayerProfile(profile);
        }
      } finally {
        if (
          isMountedRef.current &&
          profileRequestIdRef.current === requestId
        ) {
          setIsPlayerProfileLoading(false);
        }
      }
    }

    resolvePlayerProfile();

    return () => {
      isMountedRef.current = false;
      profileRequestIdRef.current += 1;
      clearPostMatchExitTimeout();
    };
  }, [
    clearPostMatchExitTimeout,
    initialPlayerProfile,
    refreshPlayerProfile,
  ]);

  useEffect(() => {
    let supabase: ReturnType<typeof createSupabaseClient>;

    try {
      supabase = createSupabaseClient();
    } catch {
      return;
    }

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange(() => {
      // Auth changes can invalidate both the iframe URL and pending match completion.
      matchCompletionPendingRef.current = false;
      setActiveGameUrl(null);
      setShowGame(false);
      refreshPlayerProfile();
    });

    return () => {
      subscription.unsubscribe();
    };
  }, [refreshPlayerProfile]);

  useEffect(() => {
    function handleGameMessage(event: MessageEvent<unknown>) {
      // Only trust messages from the iframe we opened.
      if (
        event.origin !== window.location.origin ||
        event.source !== gameWindowRef.current
      ) {
        return;
      }

      if (isExitGameMessage(event.data)) {
        if (isMatchEndExitGameMessage(event.data)) {
          // The match ended normally, so the profile modal can show progress.
          matchCompletionPendingRef.current = true;
        }
        finishPostMatchFlow();
        return;
      }

      if (isMatchSavedMessage(event.data)) {
        const matchStats = {
          deaths: Math.max(0, Math.floor(event.data.deaths)),
          durationSeconds: Math.max(0, Math.floor(event.data.duration_seconds)),
          kills: Math.max(0, Math.floor(event.data.kills)),
          matchId: event.data.match_id,
          score: Math.max(0, Math.floor(event.data.score)),
        };

        clearPostMatchExitTimeout();
        matchCompletionPendingRef.current = true;
        // Some game builds save stats before the exit packet; avoid trapping players in the iframe.
        postMatchExitTimeoutRef.current = window.setTimeout(
          finishPostMatchFlow,
          POST_MATCH_EXIT_FALLBACK_MS,
        );

        const currentProfile = playerProfileRef.current;
        const progressUpdate =
          currentProfile && !currentProfile.isGuest
            ? createOptimisticMatchProgressUpdate(
                currentProfile,
                matchStats.score,
              )
            : null;

        if (currentProfile && progressUpdate) {
          progressAnimationIdRef.current += 1;
          // Update locally first so the UI does not wait on Supabase.
          setMatchProgressAnimation({
            ...progressUpdate,
            id: progressAnimationIdRef.current,
          });

          const updatedProfile = {
            ...currentProfile,
            currentXp: progressUpdate.currentXp,
            level: progressUpdate.level,
            xpRequiredForNextLevel: progressUpdate.xpRequiredForNextLevel,
          };

          cacheAuthenticatedPlayerProfile(updatedProfile);
          setPlayerProfile(updatedProfile);
        }

        if (currentProfile && progressUpdate) {
          void saveAuthenticatedMatchResult(matchStats)
            .then(({ matchLog: savedMatch, progressUpdate: savedProgress }) => {
              if (!isMountedRef.current) {
                return;
              }

              setPlayerProfile((currentProfile) => {
                if (!currentProfile || currentProfile.isGuest) {
                  return currentProfile;
                }

                // Replace optimistic progress with the confirmed server save.
                const updatedProfile = {
                  ...currentProfile,
                  ...(savedProgress
                    ? {
                        currentXp: savedProgress.currentXp,
                        level: savedProgress.level,
                        xpRequiredForNextLevel:
                          savedProgress.xpRequiredForNextLevel,
                      }
                    : {}),
                  matchLogs: savedMatch
                    ? [
                        savedMatch,
                        ...currentProfile.matchLogs.filter(
                          (match) => match.id !== savedMatch.id,
                        ),
                      ]
                    : currentProfile.matchLogs,
                };

                cacheAuthenticatedPlayerProfile(updatedProfile);
                return updatedProfile;
              });
            })
            .catch(() => {
              // Ignore background save failures; the optimistic UI keeps the flow responsive.
            });
        }
      }
    }

    window.addEventListener("message", handleGameMessage);

    return () => {
      window.removeEventListener("message", handleGameMessage);
    };
  }, [clearPostMatchExitTimeout, finishPostMatchFlow]);

  const registerGameWindow = useCallback((gameWindow: Window | null) => {
    gameWindowRef.current = gameWindow;
  }, []);

  const nextGameUrl = playerProfile ? createGameUrl(playerProfile, language) : null;
  const gameUrl = activeGameUrl ?? nextGameUrl;
  const canPlayGame =
    !isPlayerProfileLoading &&
    nextGameUrl !== null &&
    (playerProfile?.isGuest || !playerProfile?.needsUsername);

  return {
    gameUrl,
    chatCooldownSeconds: dashboardSocket.chatCooldownSeconds,
    chatMessages: dashboardSocket.chatMessages,
    chatError: dashboardSocket.error,
    isChatConnected: dashboardSocket.isConnected,
    isPlayerProfileLoading,
    matchProgressAnimation,
    clearMatchProgressAnimation,
    onlineCount: dashboardSocket.onlineCount,
    playerProfile,
    refreshPlayerProfile,
    registerGameWindow,
    showGame,
    sendChatMessage: dashboardSocket.sendChatMessage,
    signOut: async () => {
      const supabase = createSupabaseClient();
      await supabase.auth.signOut();
      await refreshPlayerProfile();
      matchCompletionPendingRef.current = false;
      setActiveGameUrl(null);
      setShowGame(false);
    },
    deleteAccount: async () => {
      clearPostMatchExitTimeout();
      const currentProfile = playerProfileRef.current;
      if (currentProfile && !currentProfile.isGuest) {
        clearCachedAuthenticatedPlayerProfile(currentProfile.playerId);
      }
      const guestProfile = await deleteAuthenticatedPlayerAccount();
      matchCompletionPendingRef.current = false;
      loadedProfileDetailsKeyRef.current = null;
      profileDetailsRequestIdRef.current += 1;
      setMatchProgressAnimation(null);
      setActiveGameUrl(null);
      setPlayerProfile(guestProfile);
      setIsPlayerProfileLoading(false);
      setShowGame(false);
    },
    playGame: () => {
      if (canPlayGame && nextGameUrl) {
        matchCompletionPendingRef.current = false;
        clearPostMatchExitTimeout();
        setActiveGameUrl(nextGameUrl);
        setShowGame(true);
      }
    },
  };
}
