// src/components/GamePreloader.tsx

"use client";

import { useEffect } from "react";

export default function GamePreloader() {
  useEffect(() => {
    const files = [
      "/Game/index.js",
      "/Game/index.wasm",
      "/Game/index.pck",
      "/Game/index.audio.worklet.js",
      "/Game/index.worker.js",
    ];

    files.forEach((file) => {
      fetch(file, {
        cache: "force-cache",
        credentials: "same-origin",
      }).catch(() => {});
    });
  }, []);

  return null;
}