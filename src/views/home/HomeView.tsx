"use client";

import { useEffect, useState } from "react";
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
  const {
    gameUrl,
    onlineCount,
    playerProfile,
    refreshPlayerProfile,
    signOut,
    showGame,
    playGame,
  } = useHomeController();
  const needsUsernameSetup =
    playerProfile !== null && !playerProfile.isGuest && playerProfile.needsUsername;

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
        <>
          <TopBarActions
            language={language}
            onLanguageChange={setLanguage}
            onProfileClick={() => {
              if (!needsUsernameSetup) {
                setShowProfileModal(true);
              }
            }}
            playerProfile={playerProfile}
            translations={{
              ...translations.language,
              profile: translations.profile.profile,
            }}
          />
          <GlobalChat
            playerProfile={playerProfile}
            translations={translations.chat}
          />
        </>
      )}

      {!showGame && (
        <div className="absolute inset-0 z-10 flex flex-col items-center justify-center gap-6">
          <PlayButton label={translations.home.play} onClick={handlePlayGame} />

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
      )}

      {showAuthModal && (
        <AuthModal
          onClose={() => setShowAuthModal(false)}
          translations={translations.auth}
        />
      )}
      {showProfileModal && !showGame && (
        <ProfileModal
          onClose={() => setShowProfileModal(false)}
          onLogout={signOut}
          onProfileUpdated={refreshPlayerProfile}
          playerProfile={playerProfile}
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

      {showGame && gameUrl && (
        <iframe
          title="PixelFight game"
          src={gameUrl}
          className="relative z-20 h-full w-full border-0"
        />
      )}
    </main>
  );
}
