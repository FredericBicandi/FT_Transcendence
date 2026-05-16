import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  allowedDevOrigins: ["34.27.81.233"],

  async headers() {
    return [
      {
        source: "/Game/:path*",
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