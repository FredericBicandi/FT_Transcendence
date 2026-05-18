// src/app/page.tsx

"use client";

import { useState } from "react";

export default function Home() {
  const [showGame, setShowGame] = useState(false);

  return (
    <main className="relative h-screen w-screen overflow-hidden ">
      {!showGame && (
        <div className="absolute inset-0 z-10 flex flex-col items-center justify-center gap-6">
          <h1 className="text-4xl font-bold">pixelfight.42</h1>

          <button
            onClick={() => setShowGame(true)}
            className="rounded bg-blue-600 px-8 py-4 text-xl text-white hover:bg-blue-700"
          >
            Play
          </button>

          <p className="text-sm text-gray-400">
            Loading game in background...
          </p>
        </div>
      )}

      <iframe
        src="/Game/index.html"
        className="h-full w-full border-0"
        style={{
          visibility: showGame ? "visible" : "hidden",
        }}
      />
    </main>
  );
}