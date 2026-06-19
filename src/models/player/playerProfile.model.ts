"use client";

// playerProfile.model owns guest/authenticated profile normalization, XP math, match logs, and account mutations.
// It communicates with Supabase auth/tables, localStorage caches, the account API, and the static game URL contract.
// Do not casually change cache keys, username normalization, XP rollover, or fields passed into the game.

import { createSupabaseClient } from "@/models/supabase/client.model";

export type PlayerProfile = {
  playerId: string;
  playerName: string;
  avatarUrl?: string;
  currentXp: number;
  xpRequiredForNextLevel: number;
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

export type MatchProgressUpdate = {
  currentXp: number;
  level: number;
  previousCurrentXp: number;
  previousLevel: number;
  previousXpRequiredForNextLevel: number;
  xpGained: number;
  xpRequiredForNextLevel: number;
};

const PLAYER_PROFILE_STORAGE_KEY = "playerProfile";
const AUTHENTICATED_PROFILE_CACHE_KEY_PREFIX = "authenticatedPlayerProfile:";
const PLAYED_MATCHES_TABLE = "played_matches";
const MAX_GUEST_NAME_LENGTH = 10;
export const MAX_USERNAME_LENGTH = 12;
const NEW_AUTHENTICATED_PLAYER_LEVEL = 0;
const DEFAULT_XP_REQUIRED_FOR_NEXT_LEVEL = 100;
const USERNAME_TAKEN_ERROR = "USERNAME_TAKEN";
const FALLBACK_PROGRESS_REQUIREMENTS: ProgressRequirement[] = [
  { level: 0, xpRequired: 100 },
  { level: 1, xpRequired: 100 },
  { level: 2, xpRequired: 150 },
  { level: 3, xpRequired: 225 },
  { level: 4, xpRequired: 325 },
  { level: 5, xpRequired: 450 },
  { level: 6, xpRequired: 600 },
  { level: 7, xpRequired: 775 },
  { level: 8, xpRequired: 975 },
  { level: 9, xpRequired: 1200 },
  { level: 10, xpRequired: 1450 },
];

type ProfileRow = {
  current_xp: unknown;
  id: string;
  level: unknown;
  picture_url: unknown;
  username: unknown;
};

type ProgressRequirement = {
  level: number;
  xpRequired: number;
};

type LoadPlayerProfileOptions = {
  preferCache?: boolean;
};

function normalizePlayerName(value: unknown, fallback: string) {
  // Supabase rows can be null or malformed, so normalize before UI uses them.
  if (typeof value !== "string") {
    return fallback;
  }

  const normalizedName = value.trim();

  return normalizedName.length > 0 ? normalizedName : fallback;
}

function normalizeUsername(value: unknown, fallback: string) {
  if (typeof value !== "string") {
    return fallback;
  }

  const normalizedName = sanitizeUsernameInput(value);

  return normalizedName || fallback;
}

export function sanitizeUsernameInput(value: string) {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z]/g, "")
    .slice(0, MAX_USERNAME_LENGTH);
}

function normalizePlayerLevel(value: unknown, fallback = 0) {
  const numericLevel =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number(value)
        : fallback;

  return Number.isFinite(numericLevel) && numericLevel >= 0
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

  // Supabase intervals may come back as "1 day 00:00:00" strings.
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

function getUserDisplayName(userMetadata: Record<string, unknown> | undefined) {
  // OAuth providers do not agree on one display-name field.
  return (
    normalizePlayerName(userMetadata?.preferred_username, "") ||
    normalizePlayerName(userMetadata?.user_name, "") ||
    normalizePlayerName(userMetadata?.name, "") ||
    normalizePlayerName(userMetadata?.full_name, "")
  );
}

function createGuestPlayerProfile(): PlayerProfile {
  const guestNumber = Math.floor(1000 + Math.random() * 9000);
  const playerName = `Guest${guestNumber}`.slice(0, MAX_GUEST_NAME_LENGTH);

  return {
    playerId: `guest-${crypto.randomUUID()}`,
    playerName,
    currentXp: 0,
    xpRequiredForNextLevel: DEFAULT_XP_REQUIRED_FOR_NEXT_LEVEL,
    level: 0,
    isGuest: true,
    needsUsername: false,
    matchLogs: [],
  };
}

export function resetGuestPlayerProfile(): PlayerProfile {
  const playerProfile = createGuestPlayerProfile();
  localStorage.setItem(
    PLAYER_PROFILE_STORAGE_KEY,
    JSON.stringify(playerProfile),
  );

  return playerProfile;
}

function isPlayerProfile(value: unknown): value is PlayerProfile {
  // Keep localStorage from crashing the app after old or corrupted data.
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

function getAuthenticatedProfileCacheKey(playerId: string) {
  return `${AUTHENTICATED_PROFILE_CACHE_KEY_PREFIX}${playerId}`;
}

function normalizeProfileProgress(
  currentXp: number,
  level: number,
  progressRequirements: ProgressRequirement[],
) {
  let normalizedCurrentXp = currentXp;
  let normalizedLevel = level;
  let xpRequiredForNextLevel = Math.max(
    1,
    getXpRequiredForLevel(normalizedLevel, progressRequirements),
  );

  // Roll extra XP forward if cached/server progress crosses a level boundary.
  while (normalizedCurrentXp >= xpRequiredForNextLevel) {
    normalizedCurrentXp -= xpRequiredForNextLevel;
    normalizedLevel += 1;
    xpRequiredForNextLevel = Math.max(
      1,
      getXpRequiredForLevel(normalizedLevel, progressRequirements),
    );
  }

  return {
    currentXp: normalizedCurrentXp,
    level: normalizedLevel,
    xpRequiredForNextLevel,
  };
}

function loadCachedAuthenticatedPlayerProfile(playerId: string) {
  const cacheKey = getAuthenticatedProfileCacheKey(playerId);
  const savedProfile = localStorage.getItem(cacheKey);

  if (!savedProfile) {
    return null;
  }

  try {
    const parsedProfile: unknown = JSON.parse(savedProfile);

    if (isPlayerProfile(parsedProfile) && !parsedProfile.isGuest) {
      const xpRequiredForNextLevel =
        typeof parsedProfile.xpRequiredForNextLevel === "number"
          ? Math.max(1, parsedProfile.xpRequiredForNextLevel)
          : DEFAULT_XP_REQUIRED_FOR_NEXT_LEVEL;
      const normalizedProgress = normalizeProfileProgress(
        normalizeCurrentXp(parsedProfile.currentXp),
        normalizePlayerLevel(parsedProfile.level),
        [
          // Prefer the cached requirement first so offline reloads stay consistent.
          {
            level: normalizePlayerLevel(parsedProfile.level),
            xpRequired: xpRequiredForNextLevel,
          },
          ...FALLBACK_PROGRESS_REQUIREMENTS,
        ],
      );

      return {
        ...parsedProfile,
        currentXp: normalizedProgress.currentXp,
        level: normalizedProgress.level,
        xpRequiredForNextLevel: normalizedProgress.xpRequiredForNextLevel,
        matchLogs: Array.isArray(parsedProfile.matchLogs)
          ? parsedProfile.matchLogs
          : [],
      };
    }
  } catch {
    // Fall through and replace corrupted cache after the next successful load.
  }

  localStorage.removeItem(cacheKey);
  return null;
}

export function cacheAuthenticatedPlayerProfile(playerProfile: PlayerProfile) {
  if (playerProfile.isGuest) {
    return;
  }

  localStorage.setItem(
    getAuthenticatedProfileCacheKey(playerProfile.playerId),
    JSON.stringify(playerProfile),
  );
}

export function clearCachedAuthenticatedPlayerProfile(playerId: string) {
  localStorage.removeItem(getAuthenticatedProfileCacheKey(playerId));
}

function loadGuestPlayerProfile(): PlayerProfile {
  const savedProfile = localStorage.getItem(PLAYER_PROFILE_STORAGE_KEY);

  if (savedProfile) {
    try {
      const parsedProfile: unknown = JSON.parse(savedProfile);

      if (isPlayerProfile(parsedProfile)) {
        // Older cached guests may not have every newer profile field.
        return {
          ...parsedProfile,
          xpRequiredForNextLevel:
            typeof parsedProfile.xpRequiredForNextLevel === "number"
              ? parsedProfile.xpRequiredForNextLevel
              : DEFAULT_XP_REQUIRED_FOR_NEXT_LEVEL,
          matchLogs: Array.isArray(parsedProfile.matchLogs)
            ? parsedProfile.matchLogs
            : [],
        };
      }
    } catch {
      // Fall through and replace corrupted storage with a fresh guest profile.
    }
  }

  return resetGuestPlayerProfile();
}

function createAuthenticatedPlayerProfile(
  fallbackAvatarUrl: string | undefined,
  fallbackPlayerName: string,
  userId: string,
  profile: ProfileRow | null,
  matchLogs: MatchLog[],
  progressRequirements: ProgressRequirement[],
  options: { forceUsernameResolved?: boolean } = {},
) {
  const savedPlayerName = normalizePlayerName(profile?.username, "");
  const playerName =
    normalizeUsername(savedPlayerName, "") ||
    normalizeUsername(fallbackPlayerName, "");
  const level = normalizePlayerLevel(
    profile?.level,
    NEW_AUTHENTICATED_PLAYER_LEVEL,
  );
  const progress = normalizeProfileProgress(
    normalizeCurrentXp(profile?.current_xp),
    level,
    progressRequirements,
  );

  // Build one profile shape for both new and existing authenticated users.
  return {
    playerId: userId,
    playerName: playerName || "Player",
    avatarUrl: normalizeAvatarUrl(profile?.picture_url) ?? fallbackAvatarUrl,
    currentXp: progress.currentXp,
    xpRequiredForNextLevel: progress.xpRequiredForNextLevel,
    level: progress.level,
    isGuest: false,
    needsUsername: options.forceUsernameResolved ? false : !savedPlayerName,
    matchLogs,
  };
}

async function loadProgressRequirements() {
  // Keep level rules local until the database table is needed.
  return FALLBACK_PROGRESS_REQUIREMENTS;
}

function getXpRequiredForLevel(
  level: number,
  progressRequirements: ProgressRequirement[],
) {
  const normalizedLevel = normalizePlayerLevel(level);
  const requirement = progressRequirements.find(
    (progressRequirement) => progressRequirement.level === normalizedLevel,
  );

  if (
    requirement &&
    Number.isFinite(requirement.xpRequired) &&
    requirement.xpRequired > 0
  ) {
    return Math.floor(requirement.xpRequired);
  }

  const highestKnownRequirement = progressRequirements.reduce<
    ProgressRequirement | null
  >((highestRequirement, progressRequirement) => {
    if (
      !Number.isFinite(progressRequirement.xpRequired) ||
      progressRequirement.xpRequired <= 0
    ) {
      return highestRequirement;
    }

    if (
      highestRequirement === null ||
      progressRequirement.level > highestRequirement.level
    ) {
      return progressRequirement;
    }

    return highestRequirement;
  }, null);

  if (!highestKnownRequirement) {
    return DEFAULT_XP_REQUIRED_FOR_NEXT_LEVEL;
  }

  // Let high levels keep scaling even beyond the hardcoded table.
  const levelDelta = Math.max(0, normalizedLevel - highestKnownRequirement.level);

  return Math.max(
    1,
    Math.floor(highestKnownRequirement.xpRequired + levelDelta * 100),
  );
}

export function getXpRequiredForPlayerLevel(level: number) {
  return getXpRequiredForLevel(level, FALLBACK_PROGRESS_REQUIREMENTS);
}

function calculateMatchProgressUpdate({
  currentXp,
  level,
  progressRequirements,
  score,
}: {
  currentXp: number;
  level: number;
  progressRequirements: ProgressRequirement[];
  score: number;
}): MatchProgressUpdate {
  const previousLevel = level;
  const previousCurrentXp = currentXp;
  const previousXpRequiredForNextLevel = getXpRequiredForLevel(
    previousLevel,
    progressRequirements,
  );
  let nextLevel = previousLevel;
  let nextCurrentXp = previousCurrentXp + Math.max(0, Math.floor(score));
  let nextXpRequiredForNextLevel = Math.max(1, previousXpRequiredForNextLevel);

  // Apply score as XP and carry it across as many levels as needed.
  while (nextCurrentXp >= nextXpRequiredForNextLevel) {
    nextCurrentXp -= nextXpRequiredForNextLevel;
    nextLevel += 1;
    nextXpRequiredForNextLevel = getXpRequiredForLevel(
      nextLevel,
      progressRequirements,
    );
  }

  return {
    currentXp: nextCurrentXp,
    level: nextLevel,
    previousCurrentXp,
    previousLevel,
    previousXpRequiredForNextLevel,
    xpGained: Math.max(0, Math.floor(score)),
    xpRequiredForNextLevel: nextXpRequiredForNextLevel,
  };
}

function createMatchLog(row: PlayedMatchRow): MatchLog | null {
  const matchId = typeof row.match_id === "string" ? row.match_id : "";

  if (!matchId) {
    // Ignore bad rows instead of showing broken history.
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
    // History is optional; the main profile should still load.
    return [];
  }

  return (data as PlayedMatchRow[])
    .map(createMatchLog)
    .filter((row): row is MatchLog => row !== null);
}

export async function loadAuthenticatedPlayerProfileDetails({
  level,
  playerId,
}: {
  level: number;
  playerId: string;
}) {
  const [matchLogs, progressRequirements] = await Promise.all([
    loadAuthenticatedPlayerMatchLogs(playerId),
    loadProgressRequirements(),
  ]);

  return {
    matchLogs,
    xpRequiredForNextLevel: getXpRequiredForLevel(
      level,
      progressRequirements,
    ),
  };
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
    // Guests can finish matches, but only signed-in users persist logs.
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

export function createOptimisticMatchProgressUpdate(
  playerProfile: PlayerProfile,
  score: number,
) {
  return calculateMatchProgressUpdate({
    currentXp: playerProfile.currentXp,
    level: playerProfile.level,
    progressRequirements: [
      {
        level: playerProfile.level,
        xpRequired: playerProfile.xpRequiredForNextLevel,
      },
      ...FALLBACK_PROGRESS_REQUIREMENTS,
    ],
    score,
  });
}

export async function saveAuthenticatedMatchProgress(
  playerId: string,
  progressUpdate: MatchProgressUpdate,
): Promise<MatchProgressUpdate | null> {
  const supabase = createSupabaseClient();

  if (!playerId) {
    return null;
  }

  // Persist the already-computed result so optimistic UI and server state use the same XP step.
  const { error } = await supabase
    .from("profiles")
    .update({
      current_xp: progressUpdate.currentXp,
      level: progressUpdate.level,
      updated_at: new Date().toISOString(),
    })
    .eq("id", playerId);

  if (error) {
    throw error;
  }

  return progressUpdate;
}

export async function loadPlayerProfile({
  preferCache = true,
}: LoadPlayerProfileOptions = {}): Promise<PlayerProfile> {
  try {
    const supabase = createSupabaseClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (user) {
      if (preferCache) {
        const cachedProfile = loadCachedAuthenticatedPlayerProfile(user.id);

        if (cachedProfile) {
          // Return cached core profile first; the controller enriches logs after initial render.
          return cachedProfile;
        }
      }

      const userAvatarUrl = getUserAvatarUrl(user.user_metadata);
      const userDisplayName = getUserDisplayName(user.user_metadata);
      const [profileResult, progressRequirements] = await Promise.all([
        supabase
          .from("profiles")
          .select("id, level, username, current_xp, picture_url")
          .eq("id", user.id)
          .maybeSingle<ProfileRow>(),
        loadProgressRequirements(),
      ]);
      const { data, error } = profileResult;

      if (error) {
        // If profile lookup fails, use auth metadata so login still works.
        const fallbackProfile = createAuthenticatedPlayerProfile(
          userAvatarUrl,
          userDisplayName,
          user.id,
          {
            current_xp: 0,
            id: user.id,
            level: NEW_AUTHENTICATED_PLAYER_LEVEL,
            picture_url: null,
            username: userDisplayName,
          },
          [],
          progressRequirements,
          { forceUsernameResolved: true },
        );

        cacheAuthenticatedPlayerProfile(fallbackProfile);
        return fallbackProfile;
      }

      const authenticatedProfile = createAuthenticatedPlayerProfile(
        userAvatarUrl,
        userDisplayName,
        user.id,
        data,
        [],
        progressRequirements,
      );

      cacheAuthenticatedPlayerProfile(authenticatedProfile);
      return authenticatedProfile;
    }
  } catch {
    // Supabase is optional for guests, including local runs without env vars.
  }

  return loadGuestPlayerProfile();
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
  // Use upsert because profile setup can run before the row exists.
  const { error } = await supabase.from("profiles").upsert(
    {
      id: playerId,
      username: playerName,
      picture_url: avatarUrl ?? null,
    },
    { onConflict: "id" },
  );

  if (error) {
    throw error;
  }
}

export function createPlayerProfileSearchParams(playerProfile: PlayerProfile) {
  // The game reads identity from the URL because it runs inside a static export.
  const playerName = playerProfile.isGuest
    ? playerProfile.playerName
    : normalizeUsername(playerProfile.playerName, playerProfile.playerName);

  return new URLSearchParams({
    playerId: playerProfile.playerId,
    playerName,
    level: String(playerProfile.level),
    currentXp: String(playerProfile.currentXp),
  });
}

export async function isUsernameTaken(username: string, playerId: string) {
  const normalizedUsername = normalizeUsername(username, "");

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
  const normalizedPlayerName = normalizeUsername(playerName, "");

  if (!normalizedPlayerName) {
    throw new Error("USERNAME_REQUIRED");
  }

  if (await isUsernameTaken(normalizedPlayerName, playerId)) {
    // Surface a stable app error instead of leaking database details to the UI.
    throw new Error(USERNAME_TAKEN_ERROR);
  }

  await upsertProfileDetails({
    avatarUrl,
    playerId,
    playerName: normalizedPlayerName,
  });
}

export async function deleteAuthenticatedPlayerAccount() {
  const response = await fetch("/api/account", {
    method: "DELETE",
  });

  if (!response.ok) {
    throw new Error("DELETE_ACCOUNT_FAILED");
  }

  const supabase = createSupabaseClient();
  await supabase.auth.signOut().catch(() => {
    // The auth user is already deleted server-side; still clear local app state.
  });

  return resetGuestPlayerProfile();
}

export function isUsernameTakenError(error: unknown) {
  return error instanceof Error && error.message === USERNAME_TAKEN_ERROR;
}
