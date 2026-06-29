// Server-only validation for untrusted dashboard API payloads.

import "server-only";

const ALLOWED_AVATAR_MIME_TYPES = new Set([
  "image/gif",
  "image/jpeg",
  "image/png",
  "image/webp",
]);
const AVATAR_DATA_URL_PATTERN =
  /^data:(image\/(?:gif|jpeg|png|webp));base64,([A-Za-z0-9+/]+={0,2})$/;
const MAX_AVATAR_BYTES = 1024 * 1024;
const MAX_AVATAR_URL_LENGTH = 2048;
const MAX_MATCH_DURATION_SECONDS = 300;
const MAX_MATCH_SCORE = 1_000_000;
const MAX_MATCH_KILLS_OR_DEATHS = 1000;
const USERNAME_PATTERN = /^[a-z]{1,12}$/;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export class InputValidationError extends Error {}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasImageSignature(bytes: Buffer, mimeType: string) {
  if (mimeType === "image/png") {
    return bytes.subarray(0, 8).equals(
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    );
  }

  if (mimeType === "image/jpeg") {
    return (
      bytes.length >= 3 &&
      bytes[0] === 0xff &&
      bytes[1] === 0xd8 &&
      bytes[2] === 0xff
    );
  }

  if (mimeType === "image/gif") {
    const signature = bytes.subarray(0, 6).toString("ascii");
    return signature === "GIF87a" || signature === "GIF89a";
  }

  return (
    mimeType === "image/webp" &&
    bytes.subarray(0, 4).toString("ascii") === "RIFF" &&
    bytes.subarray(8, 12).toString("ascii") === "WEBP"
  );
}

function validateAvatarUrl(value: unknown) {
  if (value === undefined || value === null || value === "") {
    return null;
  }

  if (typeof value !== "string") {
    throw new InputValidationError("Avatar must be an image URL.");
  }

  if (value.startsWith("data:")) {
    const match = value.match(AVATAR_DATA_URL_PATTERN);

    if (!match || !ALLOWED_AVATAR_MIME_TYPES.has(match[1])) {
      throw new InputValidationError("Avatar image type is not allowed.");
    }

    const bytes = Buffer.from(match[2], "base64");

    if (bytes.length === 0 || bytes.length > MAX_AVATAR_BYTES) {
      throw new InputValidationError("Avatar image is too large.");
    }

    if (!hasImageSignature(bytes, match[1])) {
      throw new InputValidationError("Avatar content is not a valid image.");
    }

    return value;
  }

  if (value.length > MAX_AVATAR_URL_LENGTH) {
    throw new InputValidationError("Avatar URL is too long.");
  }

  try {
    const avatarUrl = new URL(value);

    if (avatarUrl.protocol !== "https:") {
      throw new InputValidationError("Avatar URL must use HTTPS.");
    }
  } catch (error) {
    if (error instanceof InputValidationError) {
      throw error;
    }

    throw new InputValidationError("Avatar URL is invalid.");
  }

  return value;
}

function validateBoundedInteger(
  value: unknown,
  field: string,
  maximum: number,
) {
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < 0 ||
    value > maximum
  ) {
    throw new InputValidationError(`${field} is outside the allowed range.`);
  }

  return value;
}

export function validateProfilePayload(value: unknown) {
  if (!isRecord(value)) {
    throw new InputValidationError("Profile payload must be an object.");
  }

  if (
    typeof value.username !== "string" ||
    !USERNAME_PATTERN.test(value.username)
  ) {
    throw new InputValidationError(
      "Username must contain 1 to 12 lowercase letters.",
    );
  }

  return {
    avatarUrl: validateAvatarUrl(value.avatarUrl),
    username: value.username,
  };
}

export function validateMatchPayload(value: unknown) {
  if (!isRecord(value)) {
    throw new InputValidationError("Match payload must be an object.");
  }

  if (typeof value.matchId !== "string" || !UUID_PATTERN.test(value.matchId)) {
    throw new InputValidationError("Match ID is invalid.");
  }

  return {
    deaths: validateBoundedInteger(
      value.deaths,
      "Deaths",
      MAX_MATCH_KILLS_OR_DEATHS,
    ),
    durationSeconds: validateBoundedInteger(
      value.durationSeconds,
      "Duration",
      MAX_MATCH_DURATION_SECONDS,
    ),
    kills: validateBoundedInteger(
      value.kills,
      "Kills",
      MAX_MATCH_KILLS_OR_DEATHS,
    ),
    matchId: value.matchId,
    score: validateBoundedInteger(value.score, "Score", MAX_MATCH_SCORE),
  };
}
