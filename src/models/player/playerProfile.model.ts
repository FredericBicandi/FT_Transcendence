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
  matchLogs: MatchLog[];
};

export type MatchLog = {
  deaths: number;
  durationSeconds: number;
  kills: number;
  id: number;
  matchId: string;
  playedAt: string;
  playTime: string;
  score: number;
};

type PlayedMatchRow = {
  created_at: unknown;
  deaths: unknown;
  id: unknown;
  kills: unknown;
  match_id: unknown;
  score: unknown;
  time_played: unknown;
  user_id: unknown;
};

export type MatchStatsPayload = {
  deaths: number;
  durationSeconds: number;
  kills: number;
  matchId: string;
  score: number;
};

const PLAYER_PROFILE_STORAGE_KEY = "playerProfile";
const PLAYED_MATCHES_TABLE = "played_matches";
const MAX_GUEST_NAME_LENGTH = 10;
const NEW_AUTHENTICATED_PLAYER_LEVEL = 1;
const USERNAME_TAKEN_ERROR = "USERNAME_TAKEN";

type ProfileRow = {
  current_xp: unknown;
  id: string;
  level: unknown;
  picture_url: unknown;
  username: unknown;
};

function normalizePlayerName(value: unknown, fallback: string) {
  if (typeof value !== "string") {
    return fallback;
  }

  const normalizedName = value.trim();

  return normalizedName.length > 0 ? normalizedName : fallback;
}

function normalizePlayerLevel(value: unknown, fallback = 0) {
  const numericLevel =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number(value)
        : fallback;

  return Number.isFinite(numericLevel) && numericLevel > 0
    ? Math.floor(numericLevel)
    : fallback;
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

function normalizeFiniteNumber(value: unknown, fallback = 0) {
  const numericValue =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number(value)
        : fallback;

  return Number.isFinite(numericValue) ? numericValue : fallback;
}

function formatPlayTime(durationSeconds: number) {
  const totalSeconds = Math.max(0, Math.floor(durationSeconds));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;

  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

function formatInterval(durationSeconds: number) {
  const totalSeconds = Math.max(0, Math.floor(durationSeconds));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;

  return [hours, minutes, seconds]
    .map((value) => String(value).padStart(2, "0"))
    .join(":");
}

function parseIntervalSeconds(value: unknown) {
  if (typeof value !== "string") {
    return Math.max(0, Math.floor(normalizeFiniteNumber(value)));
  }

  const match = value
    .trim()
    .match(/^(?:(\d+)\s+days?\s+)?(\d+):(\d{2}):(\d{2}(?:\.\d+)?)$/i);

  if (!match) {
    return 0;
  }

  const days = Number(match[1] ?? 0);
  const hours = Number(match[2]);
  const minutes = Number(match[3]);
  const seconds = Number(match[4]);

  return Math.max(
    0,
    Math.floor(days * 86400 + hours * 3600 + minutes * 60 + seconds),
  );
}

function formatPlayedAt(value: unknown) {
  if (typeof value !== "string") {
    return "";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat("en-US", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function getUserAvatarUrl(userMetadata: Record<string, unknown> | undefined) {
  return (
    normalizeAvatarUrl(userMetadata?.avatar_url) ??
    normalizeAvatarUrl(userMetadata?.picture)
  );
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
    matchLogs: [],
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
    typeof profile.needsUsername === "boolean" &&
    (profile.matchLogs === undefined || Array.isArray(profile.matchLogs))
  );
}

function loadGuestPlayerProfile(): PlayerProfile {
  const savedProfile = localStorage.getItem(PLAYER_PROFILE_STORAGE_KEY);

  if (savedProfile) {
    try {
      const parsedProfile: unknown = JSON.parse(savedProfile);

      if (isPlayerProfile(parsedProfile)) {
        return {
          ...parsedProfile,
          matchLogs: Array.isArray(parsedProfile.matchLogs)
            ? parsedProfile.matchLogs
            : [],
        };
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
  fallbackAvatarUrl: string | undefined,
  userId: string,
  profile: ProfileRow | null,
  matchLogs: MatchLog[],
) {
  const playerName = normalizePlayerName(profile?.username, "");

  return {
    playerId: userId,
    playerName: playerName || "Player",
    avatarUrl: normalizeAvatarUrl(profile?.picture_url) ?? fallbackAvatarUrl,
    currentXp: normalizeCurrentXp(profile?.current_xp),
    level: normalizePlayerLevel(
      profile?.level,
      NEW_AUTHENTICATED_PLAYER_LEVEL,
    ),
    isGuest: false,
    needsUsername: !playerName,
    matchLogs,
  };
}

function createMatchLog(row: PlayedMatchRow): MatchLog | null {
  const matchId = typeof row.match_id === "string" ? row.match_id : "";

  if (!matchId) {
    return null;
  }

  const durationSeconds = parseIntervalSeconds(row.time_played);

  return {
    deaths: Math.max(0, Math.floor(normalizeFiniteNumber(row.deaths))),
    durationSeconds,
    id: Math.max(0, Math.floor(normalizeFiniteNumber(row.id))),
    kills: Math.max(0, Math.floor(normalizeFiniteNumber(row.kills))),
    matchId,
    playedAt: formatPlayedAt(row.created_at),
    playTime: formatPlayTime(durationSeconds),
    score: Math.max(0, Math.floor(normalizeFiniteNumber(row.score))),
  };
}

async function loadAuthenticatedPlayerMatchLogs(playerId: string) {
  const supabase = createSupabaseClient();
  const { data, error } = await supabase
    .from(PLAYED_MATCHES_TABLE)
    .select(
      "id, match_id, user_id, score, kills, deaths, time_played, created_at",
    )
    .eq("user_id", playerId)
    .order("created_at", { ascending: false });

  if (error || !data) {
    return [];
  }

  return (data as PlayedMatchRow[])
    .map(createMatchLog)
    .filter((row): row is MatchLog => row !== null);
}

export async function saveAuthenticatedMatchLog({
  deaths,
  durationSeconds,
  kills,
  matchId,
  score,
}: MatchStatsPayload): Promise<MatchLog | null> {
  const supabase = createSupabaseClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return null;
  }

  const { data, error } = await supabase
    .from(PLAYED_MATCHES_TABLE)
    .insert({
      match_id: matchId,
      user_id: user.id,
      score,
      kills,
      deaths,
      time_played: formatInterval(durationSeconds),
    })
    .select(
      "id, match_id, user_id, score, kills, deaths, time_played, created_at",
    )
    .single<PlayedMatchRow>();

  if (error) {
    throw error;
  }

  return createMatchLog(data);
}

export async function loadPlayerProfile(): Promise<PlayerProfile> {
  try {
    const supabase = createSupabaseClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (user) {
      const userAvatarUrl = getUserAvatarUrl(user.user_metadata);
      const [profileResult, matchLogs] = await Promise.all([
        supabase
          .from("profiles")
          .select("id, level, username, current_xp, picture_url")
          .eq("id", user.id)
          .maybeSingle<ProfileRow>(),
        loadAuthenticatedPlayerMatchLogs(user.id),
      ]);
      const { data, error } = profileResult;

      if (error) {
        return createAuthenticatedPlayerProfile(
          userAvatarUrl,
          user.id,
          null,
          matchLogs,
        );
      }

      return createAuthenticatedPlayerProfile(
        userAvatarUrl,
        user.id,
        data,
        matchLogs,
      );
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
        picture_url: avatarUrl ?? null,
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
    picture_url: avatarUrl ?? null,
    level: NEW_AUTHENTICATED_PLAYER_LEVEL,
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
