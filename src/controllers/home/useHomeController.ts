"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  createPlayerProfileSearchParams,
  loadPlayerProfile,
  saveAuthenticatedMatchLog,
  type PlayerProfile,
} from "@/models/player/playerProfile.model";
import { createSupabaseClient } from "@/models/supabase/client.model";
import { useDashboardSocket } from "@/controllers/home/useDashboardSocket";

const EXIT_GAME_MESSAGE_TYPE = "EXIT_GAME";
const MATCH_SAVED_MESSAGE_TYPE = "match_saved";
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type HomeControllerOptions = {
  language: string;
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

type MatchSavedMessage = {
  deaths: number;
  duration_seconds: number;
  kills: number;
  match_id: string;
  score: number;
  type: typeof MATCH_SAVED_MESSAGE_TYPE;
};

function isMatchSavedMessage(value: unknown): value is MatchSavedMessage {
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

  return `/Game/index.html?${searchParams.toString()}`;
}

export function useHomeController({ language }: HomeControllerOptions) {
  const dashboardSocket = useDashboardSocket();
  const gameWindowRef = useRef<Window | null>(null);
  const isMountedRef = useRef(true);
  const profileRequestIdRef = useRef(0);
  const [showGame, setShowGame] = useState(false);
  const [isPlayerProfileLoading, setIsPlayerProfileLoading] = useState(true);
  const [playerProfile, setPlayerProfile] = useState<PlayerProfile | null>(
    null,
  );

  const refreshPlayerProfile = useCallback(async () => {
    const requestId = profileRequestIdRef.current + 1;
    profileRequestIdRef.current = requestId;
    setIsPlayerProfileLoading(true);

    try {
      const profile = await loadPlayerProfile();

      if (
        isMountedRef.current &&
        profileRequestIdRef.current === requestId
      ) {
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
    const requestId = profileRequestIdRef.current + 1;
    profileRequestIdRef.current = requestId;

    async function resolvePlayerProfile() {
      try {
        const profile = await loadPlayerProfile();

        if (
          isMountedRef.current &&
          profileRequestIdRef.current === requestId
        ) {
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
    };
  }, [refreshPlayerProfile]);

  useEffect(() => {
    const supabase = createSupabaseClient();
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange(() => {
      setShowGame(false);
      refreshPlayerProfile();
    });

    return () => {
      subscription.unsubscribe();
    };
  }, [refreshPlayerProfile]);

  useEffect(() => {
    function handleGameMessage(event: MessageEvent<unknown>) {
      if (
        event.origin !== window.location.origin ||
        event.source !== gameWindowRef.current
      ) {
        return;
      }

      if (isExitGameMessage(event.data)) {
        setShowGame(false);
        return;
      }

      if (isMatchSavedMessage(event.data)) {
        void saveAuthenticatedMatchLog({
          deaths: Math.max(0, Math.floor(event.data.deaths)),
          durationSeconds: Math.max(0, Math.floor(event.data.duration_seconds)),
          kills: Math.max(0, Math.floor(event.data.kills)),
          matchId: event.data.match_id,
          score: Math.max(0, Math.floor(event.data.score)),
        })
          .then((savedMatch) => {
            if (!savedMatch || !isMountedRef.current) {
              return;
            }

            setPlayerProfile((currentProfile) => {
              if (!currentProfile || currentProfile.isGuest) {
                return currentProfile;
              }

              return {
                ...currentProfile,
                matchLogs: [
                  savedMatch,
                  ...currentProfile.matchLogs.filter(
                    (match) => match.id !== savedMatch.id,
                  ),
                ],
              };
            });
          })
          .catch(() => {
            // Ignore save failures; the modal still reflects the loaded profile state.
          });
      }
    }

    window.addEventListener("message", handleGameMessage);

    return () => {
      window.removeEventListener("message", handleGameMessage);
    };
  }, []);

  const registerGameWindow = useCallback((gameWindow: Window | null) => {
    gameWindowRef.current = gameWindow;
  }, []);

  const gameUrl = playerProfile ? createGameUrl(playerProfile, language) : null;
  const canPlayGame =
    !isPlayerProfileLoading &&
    gameUrl !== null &&
    (playerProfile?.isGuest || !playerProfile?.needsUsername);

  return {
    gameUrl,
    chatMessages: dashboardSocket.chatMessages,
    chatError: dashboardSocket.error,
    isChatConnected: dashboardSocket.isConnected,
    isPlayerProfileLoading,
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
      setShowGame(false);
    },
    playGame: () => {
      if (canPlayGame) {
        setShowGame(true);
      }
    },
  };
}
