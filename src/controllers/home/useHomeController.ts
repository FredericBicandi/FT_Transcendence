"use client";

import { useCallback, useEffect, useState } from "react";
import {
  createPlayerProfileSearchParams,
  loadPlayerProfile,
  type PlayerProfile,
} from "@/models/player/playerProfile.model";
import { createSupabaseClient } from "@/models/supabase/client.model";

const ONLINE_PLAYERS_URL = "https://pixelfight.live/online";
const ONLINE_PLAYERS_POLL_INTERVAL_MS = 3_000;
const EXIT_GAME_MESSAGE_TYPE = "EXIT_GAME";

function readOnlineCount(value: unknown): number | null {
  if (typeof value === "number") {
    return Number.isFinite(value) && value >= 0 ? Math.floor(value) : null;
  }

  if (typeof value === "string") {
    const numericValue = Number(value);

    return Number.isFinite(numericValue) && numericValue >= 0
      ? Math.floor(numericValue)
      : null;
  }

  if (typeof value !== "object" || value === null) {
    return null;
  }

  const payload = value as Record<string, unknown>;

  return (
    readOnlineCount(payload.online) ??
    readOnlineCount(payload.count) ??
    readOnlineCount(payload.players) ??
    readOnlineCount(payload.onlinePlayers)
  );
}

async function fetchOnlinePlayerCount(signal: AbortSignal) {
  const response = await fetch(ONLINE_PLAYERS_URL, {
    cache: "no-store",
    signal,
  });

  if (!response.ok) {
    throw new Error("Online players request failed.");
  }

  const responseText = await response.text();

  if (!responseText.trim()) {
    throw new Error("Online players response was empty.");
  }

  try {
    const parsedPayload: unknown = JSON.parse(responseText);
    const onlineCount = readOnlineCount(parsedPayload);

    if (onlineCount !== null) {
      return onlineCount;
    }
  } catch {
    const onlineCount = readOnlineCount(responseText);

    if (onlineCount !== null) {
      return onlineCount;
    }
  }

  throw new Error("Online players response was not recognized.");
}

function isExitGameMessage(value: unknown) {
  return (
    typeof value === "object" &&
    value !== null &&
    "type" in value &&
    value.type === EXIT_GAME_MESSAGE_TYPE
  );
}

export function useHomeController() {
  const [onlineCount, setOnlineCount] = useState(0);
  const [showGame, setShowGame] = useState(false);
  const [playerProfile, setPlayerProfile] = useState<PlayerProfile | null>(
    null,
  );

  const refreshPlayerProfile = useCallback(async () => {
    const profile = await loadPlayerProfile();
    setPlayerProfile(profile);
  }, []);

  useEffect(() => {
    let mounted = true;

    async function resolvePlayerProfile() {
      const profile = await loadPlayerProfile();

      if (mounted) {
        setPlayerProfile(profile);
      }
    }

    resolvePlayerProfile();

    return () => {
      mounted = false;
    };
  }, []);

  useEffect(() => {
    const supabase = createSupabaseClient();
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange(() => {
      refreshPlayerProfile();
    });

    return () => {
      subscription.unsubscribe();
    };
  }, [refreshPlayerProfile]);

  useEffect(() => {
    let mounted = true;
    let requestInFlight = false;
    let activeController: AbortController | null = null;

    async function refreshOnlineCount() {
      if (requestInFlight) {
        return;
      }

      requestInFlight = true;
      activeController = new AbortController();

      try {
        const nextOnlineCount = await fetchOnlinePlayerCount(
          activeController.signal,
        );

        if (mounted) {
          setOnlineCount(nextOnlineCount);
        }
      } catch {
        // Keep the last known count when the live endpoint is unavailable.
      } finally {
        requestInFlight = false;
        activeController = null;
      }
    }

    refreshOnlineCount();
    const intervalId = window.setInterval(
      refreshOnlineCount,
      ONLINE_PLAYERS_POLL_INTERVAL_MS,
    );

    return () => {
      mounted = false;
      window.clearInterval(intervalId);
      activeController?.abort();
    };
  }, []);

  useEffect(() => {
    function handleGameMessage(event: MessageEvent<unknown>) {
      if (
        event.origin === window.location.origin &&
        isExitGameMessage(event.data)
      ) {
        setShowGame(false);
      }
    }

    window.addEventListener("message", handleGameMessage);

    return () => {
      window.removeEventListener("message", handleGameMessage);
    };
  }, []);

  const gameUrl = playerProfile
    ? `/Game/index.html?${createPlayerProfileSearchParams(playerProfile).toString()}`
    : null;

  return {
    gameUrl,
    onlineCount,
    playerProfile,
    refreshPlayerProfile,
    showGame,
    signOut: async () => {
      const supabase = createSupabaseClient();
      await supabase.auth.signOut();
      await refreshPlayerProfile();
      setShowGame(false);
    },
    playGame: () => {
      if (gameUrl) {
        setShowGame(true);
      }
    },
  };
}
