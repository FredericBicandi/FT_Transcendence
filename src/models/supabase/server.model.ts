// Server-only Supabase factories for authenticated API routes.
// User identity always comes from the signed session cookie, never request JSON.

import "server-only";

import { createServerClient } from "@supabase/ssr";
import type { CookieMethodsServer } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";

const supabaseCookieOptions = {
  encode: "tokens-only",
} satisfies Pick<CookieMethodsServer, "encode">;

function getRequiredEnv(name: string) {
  const value = process.env[name]?.trim();

  if (!value) {
    throw new Error(`Missing ${name}.`);
  }

  return value;
}

export async function createAuthenticatedServerClients() {
  const supabaseUrl = getRequiredEnv("NEXT_PUBLIC_SUPABASE_URL");
  const supabasePublishableKey = getRequiredEnv(
    "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
  );
  const supabaseServiceRoleKey = getRequiredEnv("SUPABASE_SERVICE_ROLE_KEY");
  const cookieStore = await cookies();
  const userClient = createServerClient(
    supabaseUrl,
    supabasePublishableKey,
    {
      cookies: {
        ...supabaseCookieOptions,
        getAll() {
          return cookieStore.getAll();
        },
        setAll() {
          // API responses do not own auth refresh; the browser client handles it.
        },
      },
    },
  );
  const {
    data: { user },
    error,
  } = await userClient.auth.getUser();

  if (error || !user) {
    return null;
  }

  const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  return { adminClient, user };
}
