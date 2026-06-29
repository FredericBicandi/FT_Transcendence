// Server-only profile loader for request-time dashboard rendering.
// It reads the authenticated Supabase cookie and returns only normalized UI data.

import "server-only";

import { createServerClient } from "@supabase/ssr";
import type { CookieMethodsServer } from "@supabase/ssr";
import { cookies } from "next/headers";
import type { PlayerProfile } from "@/models/player/playerProfile.model";

const DEFAULT_XP_REQUIRED_FOR_NEXT_LEVEL = 100;
const MAX_USERNAME_LENGTH = 12;
const PROGRESS_REQUIREMENTS = new Map<number, number>([
  [0, 100],
  [1, 100],
  [2, 150],
  [3, 225],
  [4, 325],
  [5, 450],
  [6, 600],
  [7, 775],
  [8, 975],
  [9, 1200],
  [10, 1450],
]);

type ProfileRow = {
  current_xp: unknown;
  id: string;
  level: unknown;
  picture_url: unknown;
  username: unknown;
};

const supabaseCookieOptions = {
  encode: "tokens-only",
} satisfies Pick<CookieMethodsServer, "encode">;

function normalizeString(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function normalizeUsername(value: unknown) {
  return normalizeString(value)
    .toLowerCase()
    .replace(/[^a-z]/g, "")
    .slice(0, MAX_USERNAME_LENGTH);
}

function normalizeNonNegativeInteger(value: unknown) {
  const number =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number(value)
        : 0;

  return Number.isFinite(number) && number > 0 ? Math.floor(number) : 0;
}

function getXpRequirement(level: number) {
  return (
    PROGRESS_REQUIREMENTS.get(level) ?? DEFAULT_XP_REQUIRED_FOR_NEXT_LEVEL
  );
}

function normalizeProgress(currentXpValue: unknown, levelValue: unknown) {
  let currentXp = normalizeNonNegativeInteger(currentXpValue);
  let level = normalizeNonNegativeInteger(levelValue);
  let xpRequiredForNextLevel = Math.max(1, getXpRequirement(level));

  while (currentXp >= xpRequiredForNextLevel) {
    currentXp -= xpRequiredForNextLevel;
    level += 1;
    xpRequiredForNextLevel = Math.max(1, getXpRequirement(level));
  }

  return { currentXp, level, xpRequiredForNextLevel };
}

function getMetadataName(userMetadata: Record<string, unknown>) {
  return (
    normalizeString(userMetadata.preferred_username) ||
    normalizeString(userMetadata.user_name) ||
    normalizeString(userMetadata.name) ||
    normalizeString(userMetadata.full_name)
  );
}

function getMetadataAvatar(userMetadata: Record<string, unknown>) {
  return (
    normalizeString(userMetadata.avatar_url) ||
    normalizeString(userMetadata.picture) ||
    undefined
  );
}

export async function loadServerPlayerProfile(): Promise<PlayerProfile | null> {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const supabasePublishableKey =
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();

  if (!supabaseUrl || !supabasePublishableKey) {
    return null;
  }

  try {
    const cookieStore = await cookies();
    const supabase = createServerClient(
      supabaseUrl,
      supabasePublishableKey,
      {
        cookies: {
          ...supabaseCookieOptions,
          getAll() {
            return cookieStore.getAll();
          },
          setAll() {
            // Server Components cannot set cookies; the browser client refreshes them.
          },
        },
      },
    );
    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser();

    if (userError || !user) {
      return null;
    }

    const { data, error: profileError } = await supabase
      .from("profiles")
      .select("id, level, username, current_xp, picture_url")
      .eq("id", user.id)
      .maybeSingle<ProfileRow>();

    if (profileError) {
      // Let the established browser loader apply its auth-metadata fallback.
      return null;
    }

    const metadata = user.user_metadata ?? {};
    const savedUsername = normalizeString(data?.username);
    const fallbackName = normalizeUsername(getMetadataName(metadata));
    const progress = normalizeProgress(data?.current_xp, data?.level);

    return {
      playerId: user.id,
      playerName: normalizeUsername(savedUsername) || fallbackName || "Player",
      avatarUrl:
        normalizeString(data?.picture_url) ||
        getMetadataAvatar(metadata),
      currentXp: progress.currentXp,
      xpRequiredForNextLevel: progress.xpRequiredForNextLevel,
      level: progress.level,
      isGuest: false,
      needsUsername: !savedUsername,
      matchLogs: [],
    };
  } catch {
    // Keep the dashboard available when auth or profile storage is unavailable.
    return null;
  }
}
