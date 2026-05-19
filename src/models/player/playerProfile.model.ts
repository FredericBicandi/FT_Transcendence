"use client";

import { createSupabaseClient } from "@/models/supabase/client.model";

export type PlayerProfile = {
  playerId: string;
  playerName: string;
  avatarUrl?: string;
  level: number;
  isGuest: boolean;
};

const PLAYER_PROFILE_STORAGE_KEY = "playerProfile";
const MAX_GUEST_NAME_LENGTH = 10;

function normalizePlayerName(value: unknown, fallback: string) {
  if (typeof value !== "string") {
    return fallback;
  }

  const normalizedName = value.trim();

  return normalizedName.length > 0 ? normalizedName : fallback;
}

function normalizePlayerLevel(value: unknown) {
  const numericLevel =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number(value)
        : 0;

  return Number.isFinite(numericLevel) && numericLevel > 0
    ? Math.floor(numericLevel)
    : 0;
}

function normalizeAvatarUrl(value: unknown) {
  if (typeof value !== "string") {
    return undefined;
  }

  const avatarUrl = value.trim();

  return avatarUrl.length > 0 ? avatarUrl : undefined;
}

function createGuestPlayerProfile(): PlayerProfile {
  const guestNumber = Math.floor(1000 + Math.random() * 9000);
  const playerName = `Guest${guestNumber}`.slice(0, MAX_GUEST_NAME_LENGTH);

  return {
    playerId: `guest-${crypto.randomUUID()}`,
    playerName,
    level: 0,
    isGuest: true,
  };
}

function isPlayerProfile(value: unknown): value is PlayerProfile {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const profile = value as Partial<PlayerProfile>;

  return (
    typeof profile.playerId === "string" &&
    typeof profile.playerName === "string" &&
    typeof profile.level === "number" &&
    typeof profile.isGuest === "boolean"
  );
}

function loadGuestPlayerProfile(): PlayerProfile {
  const savedProfile = localStorage.getItem(PLAYER_PROFILE_STORAGE_KEY);

  if (savedProfile) {
    try {
      const parsedProfile: unknown = JSON.parse(savedProfile);

      if (isPlayerProfile(parsedProfile)) {
        return parsedProfile;
      }
    } catch {
      // Fall through and replace corrupted storage with a fresh guest profile.
    }
  }

  const playerProfile = createGuestPlayerProfile();
  localStorage.setItem(
    PLAYER_PROFILE_STORAGE_KEY,
    JSON.stringify(playerProfile),
  );

  return playerProfile;
}

export async function loadPlayerProfile(): Promise<PlayerProfile> {
  try {
    const supabase = createSupabaseClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (user) {
      return {
        playerId: user.id,
        playerName: normalizePlayerName(
          user.user_metadata?.playerName ??
            user.user_metadata?.name ??
            user.user_metadata?.username ??
            user.user_metadata?.full_name ??
            user.email?.split("@")[0],
          "Player",
        ),
        avatarUrl: normalizeAvatarUrl(
          user.user_metadata?.avatarUrl ??
            user.user_metadata?.avatar_url ??
            user.user_metadata?.picture,
        ),
        level: normalizePlayerLevel(
          user.user_metadata?.level ?? user.app_metadata?.level,
        ),
        isGuest: false,
      };
    }
  } catch {
    // Supabase is optional for guests, including local runs without env vars.
  }

  return loadGuestPlayerProfile();
}

export function createPlayerProfileSearchParams(playerProfile: PlayerProfile) {
  return new URLSearchParams({
    playerId: playerProfile.playerId,
    playerName: playerProfile.playerName,
    level: String(playerProfile.level),
  });
}
