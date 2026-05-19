"use client";

import { useEffect, useState } from "react";
import { pingSupabase } from "@/models/supabase/client.model";
import {
  createPlayerProfileSearchParams,
  loadPlayerProfile,
  type PlayerProfile,
} from "@/models/player/playerProfile.model";

export type SupabaseStatus = "checking" | "connected" | "missing-env" | "error";

const ONLINE_PLAYERS_URL = "https://pixelfight.live/online";
const ONLINE_PLAYERS_POLL_INTERVAL_MS = 3_000;

const supabaseStatusLabels: Record<SupabaseStatus, string> = {
  checking: "Checking Supabase...",
  connected: "Supabase connected",
  "missing-env": "Supabase env missing",
  error: "Supabase connection failed",
};

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

export function useHomeController() {
  const [onlineCount, setOnlineCount] = useState(0);
  const [showGame, setShowGame] = useState(false);
  const [playerProfile, setPlayerProfile] = useState<PlayerProfile | null>(
    null,
  );
  const [supabaseStatus, setSupabaseStatus] =
    useState<SupabaseStatus>("checking");

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
    let mounted = true;

    async function checkSupabase() {
      try {
        await pingSupabase();

        if (mounted) {
          setSupabaseStatus("connected");
        }
      } catch (error) {
        if (!mounted) {
          return;
        }

        setSupabaseStatus(
          error instanceof Error &&
            error.message.includes("Missing Supabase environment variables")
            ? "missing-env"
            : "error",
        );
      }
    }

    checkSupabase();

    return () => {
      mounted = false;
    };
  }, []);

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

  const gameUrl = playerProfile
    ? `/Game/index.html?${createPlayerProfileSearchParams(playerProfile).toString()}`
    : null;

  return {
    gameUrl,
    onlineCount,
    playerProfile,
    showGame,
    supabaseStatus,
    supabaseStatusLabel: supabaseStatusLabels[supabaseStatus],
    playGame: () => {
      if (gameUrl) {
        setShowGame(true);
      }
    },
  };
}
