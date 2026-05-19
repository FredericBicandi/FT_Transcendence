// src/app/layout.tsx

import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "PXIELFIGHT",
  description: "Game dashboard",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">  
      <head>
        <link rel="prefetch" href="/game/index.js" as="script" />
        <link rel="prefetch" href="/game/index.wasm" as="fetch" crossOrigin="anonymous" />
        <link rel="prefetch" href="/game/index.pck" as="fetch" crossOrigin="anonymous" />
        <link rel="prefetch" href="/game/index.audio.worklet.js" as="script" />
      </head>
      <body>{children}</body>
    </html>
  );
}
