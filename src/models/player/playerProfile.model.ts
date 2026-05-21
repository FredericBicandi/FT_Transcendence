"use client";

import { createSupabaseClient } from "@/models/supabase/client.model";

export type PlayerProfile = {
  playerId: string;
  playerName: string;
  avatarUrl?: string;
  currentXp: number;
  level: number;
  isGuest: boolean;
  needsUsername: boolean;
};

const PLAYER_PROFILE_STORAGE_KEY = "playerProfile";
const MAX_GUEST_NAME_LENGTH = 10;
const USERNAME_TAKEN_ERROR = "USERNAME_TAKEN";

type ProfileRow = {
  current_xp: unknown;
  id: string;
  level: unknown;
  profile_url: unknown;
  username: unknown;
};

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

function normalizeCurrentXp(value: unknown) {
  const numericXp =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number(value)
        : 0;

  return Number.isFinite(numericXp) && numericXp > 0 ? Math.floor(numericXp) : 0;
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
    currentXp: 0,
    level: 0,
    isGuest: true,
    needsUsername: false,
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
    typeof profile.currentXp === "number" &&
    typeof profile.level === "number" &&
    typeof profile.isGuest === "boolean" &&
    typeof profile.needsUsername === "boolean"
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

function createAuthenticatedPlayerProfile(
  userId: string,
  profile: ProfileRow | null,
) {
  const playerName = normalizePlayerName(profile?.username, "");

  return {
    playerId: userId,
    playerName: playerName || "Player",
    avatarUrl: normalizeAvatarUrl(profile?.profile_url),
    currentXp: normalizeCurrentXp(profile?.current_xp),
    level: normalizePlayerLevel(profile?.level),
    isGuest: false,
    needsUsername: !playerName,
  };
}

export async function loadPlayerProfile(): Promise<PlayerProfile> {
  try {
    const supabase = createSupabaseClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (user) {
      const { data, error } = await supabase
        .from("profiles")
        .select("id, level, username, current_xp, profile_url")
        .eq("id", user.id)
        .maybeSingle<ProfileRow>();

      if (error) {
        return createAuthenticatedPlayerProfile(user.id, null);
      }

      return createAuthenticatedPlayerProfile(user.id, data);
    }
  } catch {
    // Supabase is optional for guests, including local runs without env vars.
  }

  return loadGuestPlayerProfile();
}

async function profileExists(playerId: string) {
  const supabase = createSupabaseClient();
  const { data, error } = await supabase
    .from("profiles")
    .select("id")
    .eq("id", playerId)
    .maybeSingle<{ id: string }>();

  if (error) {
    throw error;
  }

  return data !== null;
}

async function upsertProfileDetails({
  avatarUrl,
  playerId,
  playerName,
}: {
  avatarUrl?: string;
  playerId: string;
  playerName: string;
}) {
  const supabase = createSupabaseClient();

  if (await profileExists(playerId)) {
    const { error } = await supabase
      .from("profiles")
      .update({
        username: playerName,
        profile_url: avatarUrl ?? null,
      })
      .eq("id", playerId);

    if (error) {
      throw error;
    }

    return;
  }

  const { error } = await supabase.from("profiles").insert({
    id: playerId,
    username: playerName,
    profile_url: avatarUrl ?? null,
    level: 0,
    current_xp: 0,
  });

  if (error) {
    throw error;
  }
}

export function createPlayerProfileSearchParams(playerProfile: PlayerProfile) {
  return new URLSearchParams({
    playerId: playerProfile.playerId,
    playerName: playerProfile.playerName,
    level: String(playerProfile.level),
    currentXp: String(playerProfile.currentXp),
  });
}

export async function isUsernameTaken(username: string, playerId: string) {
  const normalizedUsername = normalizePlayerName(username, "");

  if (!normalizedUsername) {
    return false;
  }

  const supabase = createSupabaseClient();
  const { data, error } = await supabase
    .from("profiles")
    .select("id")
    .ilike("username", normalizedUsername)
    .neq("id", playerId)
    .limit(1);

  if (error) {
    throw error;
  }

  return data.length > 0;
}

export async function saveAuthenticatedPlayerProfile({
  avatarUrl,
  playerId,
  playerName,
}: {
  avatarUrl?: string;
  playerId: string;
  playerName: string;
}) {
  const normalizedPlayerName = normalizePlayerName(playerName, "");

  if (!normalizedPlayerName) {
    throw new Error("USERNAME_REQUIRED");
  }

  if (await isUsernameTaken(normalizedPlayerName, playerId)) {
    throw new Error(USERNAME_TAKEN_ERROR);
  }

  await upsertProfileDetails({
    avatarUrl,
    playerId,
    playerName: normalizedPlayerName,
  });
}

export function isUsernameTakenError(error: unknown) {
  return error instanceof Error && error.message === USERNAME_TAKEN_ERROR;
}
