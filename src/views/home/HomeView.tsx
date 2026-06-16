"use client";

import Image from "next/image";
import { useCallback, useEffect, useState } from "react";
import { AuthModal } from "@/components/home/AuthModal";
import { LoginSignupButton } from "@/components/home/LoginSignupButton";
import { GlobalChat } from "@/components/home/GlobalChat";
import { OnlinePlayersBadge } from "@/components/home/OnlinePlayersBadge";
import { PlayButton } from "@/components/home/PlayButton";
import { ProfileModal } from "@/components/home/ProfileModal";
import { TopBarActions } from "@/components/home/TopBarActions";
import { UsernameSetupModal } from "@/components/home/UsernameSetupModal";
import { useHomeController } from "@/controllers/home/useHomeController";
import {
  homeTranslations,
  type HomeLanguage,
} from "@/views/home/homeTranslations";

const LANGUAGE_STORAGE_KEY = "homeLanguage";

function isHomeLanguage(value: string | null): value is HomeLanguage {
  return value === "english" || value === "french" || value === "arabic";
}

export function HomeView() {
  const [showAuthModal, setShowAuthModal] = useState(false);
  const [showProfileModal, setShowProfileModal] = useState(false);
  const [language, setLanguage] = useState<HomeLanguage>("english");
  const translations = homeTranslations[language];
  const openProfileAfterMatch = useCallback(() => {
    setShowProfileModal(true);
  }, []);
  const {
    chatError,
    chatMessages,
    clearMatchProgressAnimation,
    gameUrl,
    isChatConnected,
    isPlayerProfileLoading,
    matchProgressAnimation,
    onlineCount,
    playerProfile,
    deleteAccount,
    refreshPlayerProfile,
    registerGameWindow,
    sendChatMessage,
    signOut,
    showGame,
    playGame,
  } = useHomeController({
    language,
    onMatchComplete: openProfileAfterMatch,
  });
  const needsUsernameSetup =
    !isPlayerProfileLoading &&
    playerProfile !== null &&
    !playerProfile.isGuest &&
    playerProfile.needsUsername;

  useEffect(() => {
    const savedLanguage = window.localStorage.getItem(LANGUAGE_STORAGE_KEY);

    if (isHomeLanguage(savedLanguage)) {
      window.setTimeout(() => setLanguage(savedLanguage), 0);
    }
  }, []);

  useEffect(() => {
    window.localStorage.setItem(LANGUAGE_STORAGE_KEY, language);
  }, [language]);

  function handlePlayGame() {
    setShowProfileModal(false);
    playGame();
  }

  return (
    <main
      className="relative h-screen w-screen overflow-hidden bg-black"
      dir={language === "arabic" ? "rtl" : "ltr"}
      lang={language === "arabic" ? "ar" : language === "french" ? "fr" : "en"}
    >
      <div
        className="absolute inset-0 bg-[url('/images/map.png')] bg-cover bg-center bg-no-repeat opacity-80 [image-rendering:pixelated]"
        aria-hidden="true"
      />
      <div
        className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,rgba(0,0,0,0.18)_0%,rgba(0,0,0,0.78)_86%)]"
        aria-hidden="true"
      />

      {!showGame && (
        <TopBarActions
          language={language}
          onLanguageChange={setLanguage}
          onProfileClick={() => {
            if (!isPlayerProfileLoading && !needsUsernameSetup) {
              setShowProfileModal(true);
            }
          }}
          playerProfile={playerProfile}
          translations={{
            ...translations.fullscreen,
            ...translations.language,
            profile: translations.profile.profile,
          }}
        />
      )}

      {!showGame && (
        <div className="absolute inset-0 z-10 flex items-center justify-center gap-8 px-4">
          <div className="hidden w-[28rem] lg:block" aria-hidden="true" />

          <div className="flex flex-col items-center gap-6">
            <div className="flex flex-col items-center gap-4 text-center">
              <Image
                src="/images/icon.png"
                alt="Pixel Fight icon"
                width={112}
                height={112}
                priority
                className="h-24 w-24 animate-[float_3s_ease-in-out_infinite] drop-shadow-[0_6px_0_rgba(5,3,2,0.65)] [image-rendering:pixelated] sm:h-28 sm:w-28"
              />
              <div className="flex flex-col items-center gap-2">
                <h1 className="text-5xl font-bold uppercase leading-none tracking-[0.08em] text-[#f5dfad] [text-shadow:0_4px_0_#050302,4px_0_0_#050302,0_-4px_0_#050302,-4px_0_0_#050302,4px_4px_0_#050302] sm:text-7xl">
                  PIXEL FIGHT
                </h1>
                <div className="flex w-full items-center justify-center gap-3">
                  <span className="h-[3px] w-12 bg-[#f5dfad]/40 shadow-[0_1px_0_#050302]" />
                  <span className="text-xs font-bold uppercase tracking-[0.35em] text-[#f5dfad]/80 [text-shadow:0_2px_0_#050302] sm:text-sm">
                    Battle Arena
                  </span>
                  <span className="h-[3px] w-12 bg-[#f5dfad]/40 shadow-[0_1px_0_#050302]" />
                </div>
              </div>
            </div>

            {isPlayerProfileLoading ? (
              <div className="bg-[#151819] px-6 py-4 text-sm uppercase text-[#f5dfad] shadow-[0_0_0_3px_#050302,0_4px_0_3px_#111515,inset_0_3px_0_#374041,inset_0_-3px_0_#050302]">
                {translations.home.loading}
              </div>
            ) : (
              <PlayButton
                disabled={!gameUrl || needsUsernameSetup}
                label={translations.home.play}
                onClick={handlePlayGame}
              />
            )}

            <OnlinePlayersBadge
              label={translations.home.online}
              onlineCount={onlineCount}
            />

            {playerProfile?.isGuest && (
              <LoginSignupButton
                label={translations.home.loginSignup}
                onClick={() => setShowAuthModal(true)}
              />
            )}
          </div>

          <GlobalChat
            errorMessage={chatError?.message ?? null}
            isConnected={isChatConnected}
            messages={chatMessages}
            onSendMessage={sendChatMessage}
            playerProfile={playerProfile}
            translations={translations.chat}
          />
        </div>
      )}

      {showAuthModal && (
        <AuthModal
          onClose={() => setShowAuthModal(false)}
          translations={translations.auth}
        />
      )}
      {showProfileModal && !showGame && (
        <ProfileModal
          key={playerProfile?.playerId ?? "loading"}
          onClose={() => setShowProfileModal(false)}
          onDeleteAccount={deleteAccount}
          onLogout={signOut}
          onProgressAnimationSeen={clearMatchProgressAnimation}
          onProfileUpdated={refreshPlayerProfile}
          playerProfile={playerProfile}
          progressAnimation={matchProgressAnimation}
          translations={translations.profile}
        />
      )}
      {needsUsernameSetup && (
        <UsernameSetupModal
          onProfileUpdated={refreshPlayerProfile}
          playerProfile={playerProfile}
          translations={translations.profile}
        />
      )}

      {gameUrl && !needsUsernameSetup && (
        <iframe
          title="PixelFight game"
          ref={(frame) => registerGameWindow(frame?.contentWindow ?? null)}
          src={gameUrl}
          className={`absolute inset-0 z-20 h-full w-full border-0 ${
            showGame ? "visible" : "invisible pointer-events-none"
          }`}
        />
      )}
    </main>
  );
}
