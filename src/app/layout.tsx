// src/app/layout.tsx

import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "PXIELFIGHT",
  description: "Game dashboard",
  icons: {
    icon: "/icon.png",
    shortcut: "/favicon.ico",
    apple: "/icon.png",
  },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">  
      <head>
        <link rel="prefetch" href="/Game/index.js" as="script" />
        <link
          rel="prefetch"
          href="/Game/index.wasm"
          as="fetch"
          crossOrigin="anonymous"
        />
        <link
          rel="prefetch"
          href="/Game/index.pck"
          as="fetch"
          crossOrigin="anonymous"
        />
        <link rel="prefetch" href="/Game/index.audio.worklet.js" as="script" />
      </head>
      <body>{children}</body>
    </html>
  );
}
