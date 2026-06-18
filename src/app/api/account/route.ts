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

function createErrorResponse(message: string, status: number) {
  return NextResponse.json({ error: message }, { status });
}

export async function DELETE() {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabasePublishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !supabasePublishableKey || !supabaseServiceRoleKey) {
    return createErrorResponse("Account deletion is not configured.", 500);
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
    return createErrorResponse("Not authenticated.", 401);
  }

  // Use the service role only after proving the request owns this session.
  const adminSupabase = createClient(supabaseUrl, supabaseServiceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
  const { error: deleteUserError } =
    await adminSupabase.auth.admin.deleteUser(user.id);

  if (deleteUserError) {
    return createErrorResponse("Could not delete account.", 500);
  }

  return NextResponse.json({ ok: true });
}
