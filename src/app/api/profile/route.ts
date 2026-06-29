// Authenticated profile writes with server-side username and avatar validation.

import { NextResponse } from "next/server";
import { createAuthenticatedServerClients } from "@/models/supabase/server.model";
import {
  InputValidationError,
  validateProfilePayload,
} from "@/models/validation/serverInputValidation.model";

const MAX_PROFILE_BODY_LENGTH = 1_500_000;

function errorResponse(code: string, message: string, status: number) {
  return NextResponse.json({ code, error: message }, { status });
}

export async function PATCH(request: Request) {
  try {
    const requestBody = await request.text();

    if (requestBody.length > MAX_PROFILE_BODY_LENGTH) {
      return errorResponse("AVATAR_TOO_LARGE", "Profile payload is too large.", 413);
    }

    let parsedBody: unknown;

    try {
      parsedBody = JSON.parse(requestBody);
    } catch {
      return errorResponse("INVALID_JSON", "Request body is not valid JSON.", 400);
    }

    const profile = validateProfilePayload(parsedBody);
    const clients = await createAuthenticatedServerClients();

    if (!clients) {
      return errorResponse("UNAUTHENTICATED", "Authentication is required.", 401);
    }

    const { adminClient, user } = clients;
    const { data: duplicateUsername, error: duplicateLookupError } =
      await adminClient
        .from("profiles")
        .select("id")
        .ilike("username", profile.username)
        .neq("id", user.id)
        .limit(1)
        .maybeSingle();

    if (duplicateLookupError) {
      throw duplicateLookupError;
    }

    if (duplicateUsername) {
      return errorResponse("USERNAME_TAKEN", "Username is already taken.", 409);
    }

    const { error } = await adminClient.from("profiles").upsert(
      {
        id: user.id,
        picture_url: profile.avatarUrl,
        updated_at: new Date().toISOString(),
        username: profile.username,
      },
      { onConflict: "id" },
    );

    if (error?.code === "23505") {
      return errorResponse("USERNAME_TAKEN", "Username is already taken.", 409);
    }

    if (error) {
      throw error;
    }

    return NextResponse.json({
      avatarUrl: profile.avatarUrl,
      username: profile.username,
    });
  } catch (error) {
    if (error instanceof InputValidationError) {
      return errorResponse("INVALID_PROFILE", error.message, 400);
    }

    console.error("Validated profile update failed.", error);
    return errorResponse("PROFILE_SAVE_FAILED", "Could not save profile.", 500);
  }
}
