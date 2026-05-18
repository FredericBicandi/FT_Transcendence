import { createBrowserClient } from "@supabase/ssr";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabasePublishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

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
  );
}

export async function pingSupabase() {
  const config = getSupabaseConfig();
  const response = await fetch(new URL("/auth/v1/settings", config.supabaseUrl), {
    headers: {
      apikey: config.supabasePublishableKey,
    },
  });

  if (!response.ok) {
    throw new Error("Supabase connection failed.");
  }
}
