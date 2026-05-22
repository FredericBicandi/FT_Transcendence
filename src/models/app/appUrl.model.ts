const CANONICAL_APP_URL = "https://pixelfight.live";
const LOCAL_HOSTNAMES = new Set(["localhost", "127.0.0.1", "0.0.0.0"]);

function stripTrailingSlashes(url: string) {
  return url.replace(/\/+$/, "");
}

function normalizeAppUrl(url: string) {
  const normalizedUrl = stripTrailingSlashes(url);

  try {
    const { hostname, protocol } = new URL(normalizedUrl);

    if (protocol !== "http:" && protocol !== "https:") {
      return null;
    }

    return {
      hostname,
      url: normalizedUrl,
    };
  } catch {
    return null;
  }
}

export function getAppUrl() {
  const configuredAppUrl = process.env.NEXT_PUBLIC_APP_URL?.trim();

  if (!configuredAppUrl) {
    return CANONICAL_APP_URL;
  }

  const appUrl = normalizeAppUrl(configuredAppUrl);

  if (!appUrl) {
    return CANONICAL_APP_URL;
  }

  if (
    process.env.NODE_ENV === "production" &&
    LOCAL_HOSTNAMES.has(appUrl.hostname)
  ) {
    return CANONICAL_APP_URL;
  }

  return appUrl.url;
}

export function getAuthCallbackUrl() {
  return `${getAppUrl()}/auth/callback`;
}
