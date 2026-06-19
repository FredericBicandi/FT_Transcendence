// Account API owns authenticated account deletion.
// It communicates with Supabase SSR auth cookies and the Supabase admin client.
// Do not casually change the session proof before service-role deletion.

import { createServerClient } from "@supabase/ssr";
import type { CookieMethodsServer } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";
import { NextResponse } from "next/server";

const supabaseCookieOptions = {
  // Keep Supabase cookies compatible with the SSR helper.
  encode: "tokens-only",
} satisfies Pick<CookieMethodsServer, "encode">;

function createErrorResponse(message: string, status: number, code: string) {
  return NextResponse.json({ code, error: message }, { status });
}

function getEnvValue(name: string) {
  const value = process.env[name]?.trim();

  return value || undefined;
}

function logAccountDeletionError(step: string, error: unknown) {
  console.error("Account deletion failed.", { step, error });
}

export async function DELETE() {
  const supabaseUrl = getEnvValue("NEXT_PUBLIC_SUPABASE_URL");
  const supabasePublishableKey = getEnvValue(
    "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
  );
  const supabaseServiceRoleKey = getEnvValue("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !supabasePublishableKey || !supabaseServiceRoleKey) {
    logAccountDeletionError("configuration", {
      hasPublishableKey: Boolean(supabasePublishableKey),
      hasServiceRoleKey: Boolean(supabaseServiceRoleKey),
      hasUrl: Boolean(supabaseUrl),
    });
    return createErrorResponse(
      "Account deletion is not configured.",
      500,
      "ACCOUNT_DELETE_CONFIG",
    );
  }

  const cookieStore = await cookies();
  const userSupabase = createServerClient(
    supabaseUrl,
    supabasePublishableKey,
    {
      cookies: {
        ...supabaseCookieOptions,
        getAll() {
          return cookieStore.getAll();
        },
        setAll() {
          // The client signs out after account deletion succeeds.
        },
      },
    },
  );
  const {
    data: { user },
    error: userError,
  } = await userSupabase.auth.getUser();

  if (userError || !user) {
    return createErrorResponse(
      "Not authenticated.",
      401,
      "ACCOUNT_DELETE_UNAUTHENTICATED",
    );
  }

  // Use the service role only after proving the request owns this session.
  const adminSupabase = createClient(supabaseUrl, supabaseServiceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const { error: deletePlayedMatchesError } = await adminSupabase
    .from("played_matches")
    .delete()
    .eq("user_id", user.id);

  if (deletePlayedMatchesError) {
    logAccountDeletionError("played_matches", deletePlayedMatchesError);
    return createErrorResponse(
      "Could not delete account.",
      500,
      "ACCOUNT_DELETE_PLAYED_MATCHES",
    );
  }

  const { error: deleteProfileError } = await adminSupabase
    .from("profiles")
    .delete()
    .eq("id", user.id);

  if (deleteProfileError) {
    logAccountDeletionError("profiles", deleteProfileError);
    return createErrorResponse(
      "Could not delete account.",
      500,
      "ACCOUNT_DELETE_PROFILE",
    );
  }

  const { error: deleteUserError } =
    await adminSupabase.auth.admin.deleteUser(user.id);

  if (deleteUserError) {
    logAccountDeletionError("auth.users", deleteUserError);
    return createErrorResponse(
      "Could not delete account.",
      500,
      "ACCOUNT_DELETE_AUTH_USER",
    );
  }

  return NextResponse.json({ ok: true });
}
