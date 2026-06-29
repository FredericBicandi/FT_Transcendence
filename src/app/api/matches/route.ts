// Authenticated match-result persistence with bounded, server-validated statistics.

import { NextResponse } from "next/server";
import { createAuthenticatedServerClients } from "@/models/supabase/server.model";
import {
  InputValidationError,
  validateMatchPayload,
} from "@/models/validation/serverInputValidation.model";

const MAX_MATCH_BODY_LENGTH = 4096;
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

type MatchRow = {
  duration_seconds: unknown;
  id: string;
};

type ProfileProgressRow = {
  current_xp: unknown;
  level: unknown;
};

function errorResponse(code: string, message: string, status: number) {
  return NextResponse.json({ code, error: message }, { status });
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
  const knownRequirement = PROGRESS_REQUIREMENTS.get(level);

  if (knownRequirement !== undefined) {
    return knownRequirement;
  }

  return level > 10 ? 1450 + (level - 10) * 100 : 100;
}

function calculateProgress(
  currentXpValue: unknown,
  levelValue: unknown,
  score: number,
) {
  const previousCurrentXp = normalizeNonNegativeInteger(currentXpValue);
  const previousLevel = normalizeNonNegativeInteger(levelValue);
  const previousXpRequiredForNextLevel = getXpRequirement(previousLevel);
  let currentXp = previousCurrentXp + score;
  let level = previousLevel;
  let xpRequiredForNextLevel = previousXpRequiredForNextLevel;

  while (currentXp >= xpRequiredForNextLevel) {
    currentXp -= xpRequiredForNextLevel;
    level += 1;
    xpRequiredForNextLevel = getXpRequirement(level);
  }

  return {
    currentXp,
    level,
    previousCurrentXp,
    previousLevel,
    previousXpRequiredForNextLevel,
    xpGained: score,
    xpRequiredForNextLevel,
  };
}

function formatInterval(durationSeconds: number) {
  const minutes = Math.floor(durationSeconds / 60);
  const seconds = durationSeconds % 60;

  return `00:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
}

export async function POST(request: Request) {
  try {
    const requestBody = await request.text();

    if (requestBody.length > MAX_MATCH_BODY_LENGTH) {
      return errorResponse("PAYLOAD_TOO_LARGE", "Match payload is too large.", 413);
    }

    let parsedBody: unknown;

    try {
      parsedBody = JSON.parse(requestBody);
    } catch {
      return errorResponse("INVALID_JSON", "Request body is not valid JSON.", 400);
    }

    const matchStats = validateMatchPayload(parsedBody);
    const clients = await createAuthenticatedServerClients();

    if (!clients) {
      return errorResponse("UNAUTHENTICATED", "Authentication is required.", 401);
    }

    const { adminClient, user } = clients;
    const { data: match, error: matchError } = await adminClient
      .from("matches")
      .select("id, duration_seconds")
      .eq("id", matchStats.matchId)
      .maybeSingle<MatchRow>();

    if (matchError) {
      throw matchError;
    }

    if (!match) {
      return errorResponse(
        "MATCH_NOT_FOUND",
        "The authoritative game server has not saved this match.",
        409,
      );
    }

    const matchDuration = normalizeNonNegativeInteger(match.duration_seconds);

    if (matchStats.durationSeconds > matchDuration) {
      return errorResponse(
        "INVALID_MATCH_DURATION",
        "Player duration exceeds the saved match duration.",
        400,
      );
    }

    const { data: existingResult, error: existingResultError } =
      await adminClient
        .from("played_matches")
        .select("id")
        .eq("match_id", matchStats.matchId)
        .eq("user_id", user.id)
        .limit(1)
        .maybeSingle();

    if (existingResultError) {
      throw existingResultError;
    }

    if (existingResult) {
      return errorResponse(
        "MATCH_ALREADY_SAVED",
        "This match result has already been saved.",
        409,
      );
    }

    const { data: profile, error: profileError } = await adminClient
      .from("profiles")
      .select("current_xp, level")
      .eq("id", user.id)
      .maybeSingle<ProfileProgressRow>();

    if (profileError) {
      throw profileError;
    }

    if (!profile) {
      return errorResponse(
        "PROFILE_REQUIRED",
        "Create a player profile before saving match statistics.",
        409,
      );
    }

    const progressUpdate = calculateProgress(
      profile.current_xp,
      profile.level,
      matchStats.score,
    );
    const { data: playedMatch, error: insertError } = await adminClient
      .from("played_matches")
      .insert({
        deaths: matchStats.deaths,
        kills: matchStats.kills,
        match_id: matchStats.matchId,
        score: matchStats.score,
        time_played: formatInterval(matchStats.durationSeconds),
        user_id: user.id,
      })
      .select(
        "id, match_id, user_id, score, kills, deaths, time_played, created_at",
      )
      .single();

    if (insertError?.code === "23505") {
      return errorResponse(
        "MATCH_ALREADY_SAVED",
        "This match result has already been saved.",
        409,
      );
    }

    if (insertError) {
      throw insertError;
    }

    const { error: progressError } = await adminClient
      .from("profiles")
      .update({
        current_xp: progressUpdate.currentXp,
        level: progressUpdate.level,
        updated_at: new Date().toISOString(),
      })
      .eq("id", user.id);

    if (progressError) {
      // Compensate for the failed second write so a retry remains possible.
      await adminClient.from("played_matches").delete().eq("id", playedMatch.id);
      throw progressError;
    }

    return NextResponse.json({ playedMatch, progressUpdate });
  } catch (error) {
    if (error instanceof InputValidationError) {
      return errorResponse("INVALID_MATCH", error.message, 400);
    }

    console.error("Validated match save failed.", error);
    return errorResponse("MATCH_SAVE_FAILED", "Could not save match.", 500);
  }
}
