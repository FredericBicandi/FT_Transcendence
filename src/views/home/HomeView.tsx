"use client";

import { LoginSignupButton } from "@/components/home/LoginSignupButton";
import { OnlinePlayersBadge } from "@/components/home/OnlinePlayersBadge";
import { PlayButton } from "@/components/home/PlayButton";
import { SupabaseStatusBadge } from "@/components/home/SupabaseStatusBadge";
import { useHomeController } from "@/controllers/home/useHomeController";

export function HomeView() {
  const {
    gameUrl,
    onlineCount,
    showGame,
    supabaseStatus,
    supabaseStatusLabel,
    playGame,
  } = useHomeController();

  return (
    <main className="relative h-screen w-screen overflow-hidden bg-black">
      <div
        className="absolute inset-0 bg-[url('/images/map.png')] bg-cover bg-center bg-no-repeat opacity-80 [image-rendering:pixelated]"
        aria-hidden="true"
      />
      <div
        className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,rgba(0,0,0,0.18)_0%,rgba(0,0,0,0.78)_86%)]"
        aria-hidden="true"
      />

      {!showGame && (
        <div className="absolute inset-0 z-10 flex flex-col items-center justify-center gap-6">
          <PlayButton onClick={playGame} />

          <OnlinePlayersBadge onlineCount={onlineCount} />

          <LoginSignupButton />

          <p className="text-sm text-gray-400">
            {gameUrl ? "Loading game in background..." : "Preparing player..."}
          </p>

          <SupabaseStatusBadge
            label={supabaseStatusLabel}
            status={supabaseStatus}
          />
        </div>
      )}

      {gameUrl && (
        <iframe
          title="PixelFight game"
          src={gameUrl}
          className="relative z-20 h-full w-full border-0"
          style={{
            visibility: showGame ? "visible" : "hidden",
          }}
        />
      )}
    </main>
  );
}
