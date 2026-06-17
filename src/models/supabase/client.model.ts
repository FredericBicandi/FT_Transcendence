import { createBrowserClient } from "@supabase/ssr";
import type { CookieMethodsBrowser } from "@supabase/ssr";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabasePublishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
const supabaseCookieOptions = {
  // Keep browser cookies in the same format as the server auth callback.
  encode: "tokens-only",
} satisfies Pick<CookieMethodsBrowser, "encode">;

function getSupabaseConfig() {
  if (!supabaseUrl || !supabasePublishableKey) {
    throw new Error("Missing Supabase environment variables.");
  }

  return {
    supabaseUrl,
    supabasePublishableKey,
  };
}

export function createSupabaseClient() {
  const config = getSupabaseConfig();

  return createBrowserClient(
    config.supabaseUrl,
    config.supabasePublishableKey,
    {
      cookies: supabaseCookieOptions,
      global: {
        headers: {
          // Some Supabase REST calls need apikey even when auth cookies exist.
          apikey: config.supabasePublishableKey,
        },
      },
    },
  );
}

export async function pingSupabase() {
  const config = getSupabaseConfig();
  // Hit a lightweight auth endpoint so startup checks do not touch game data.
  const response = await fetch(new URL("/auth/v1/settings", config.supabaseUrl), {
    headers: {
      apikey: config.supabasePublishableKey,
    },
  });

  if (!response.ok) {
    throw new Error("Supabase connection failed.");
  }
}
