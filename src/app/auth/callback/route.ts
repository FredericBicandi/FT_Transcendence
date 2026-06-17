import { createServerClient } from "@supabase/ssr";
import type { CookieMethodsServer } from "@supabase/ssr";
import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { getAppUrl } from "@/models/app/appUrl.model";

const supabaseCookieOptions = {
  // Match the cookie format expected by the Supabase SSR client.
  encode: "tokens-only",
} satisfies Pick<CookieMethodsServer, "encode">;

function getRedirectUrl(authError?: string) {
  const redirectUrl = new URL(getAppUrl());

  if (authError) {
    redirectUrl.searchParams.set("auth_error", authError);
  }

  return redirectUrl;
}

export async function GET(request: Request) {
  const requestUrl = new URL(request.url);
  const code = requestUrl.searchParams.get("code");
  const redirectResponse = NextResponse.redirect(getRedirectUrl());

  if (code) {
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const supabasePublishableKey =
      process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

    if (!supabaseUrl || !supabasePublishableKey) {
      return NextResponse.redirect(getRedirectUrl("config"));
    }

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
          setAll(cookiesToSet, headers) {
            // Store the new auth cookies on the redirect response itself.
            cookiesToSet.forEach(({ name, value, options }) => {
              redirectResponse.cookies.set(name, value, options);
            });
            Object.entries(headers).forEach(([key, value]) => {
              redirectResponse.headers.set(key, value);
            });
          },
        },
      },
    );

    const { error } = await supabase.auth.exchangeCodeForSession(code);

    if (error) {
      return NextResponse.redirect(getRedirectUrl(error.code ?? "oauth"));
    }
  }

  return redirectResponse;
}
