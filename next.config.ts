import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  allowedDevOrigins: ["34.27.81.233"],

  async rewrites() {
    return [
      {
        source: "/game",
        destination: "/Game/index.html",
      },
      {
        source: "/game/",
        destination: "/Game/index.html",
      },
      {
        source: "/game/:path*",
        destination: "/Game/:path*",
      },
    ];
  },

  async headers() {
    return [
      {
        source: "/:gamePath(Game|game)/:path*",
        headers: [
          {
            key: "Cache-Control",
            value: "public, max-age=31536000, immutable",
          },
        ],
      },
    ];
  },
};

export default nextConfig;
