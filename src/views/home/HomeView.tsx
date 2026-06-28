"use client";

// HomeView owns the dashboard shell and embedded Godot iframe.
// It communicates with useHomeController, localStorage, and postMessage.
// Do not casually change iframe origin checks or hydration timing.

import Image from "next/image";
import { useCallback, useEffect, useState } from "react";
import { AuthModal } from "@/components/home/AuthModal";
import { LoginSignupButton } from "@/components/home/LoginSignupButton";
import { GlobalChat } from "@/components/home/GlobalChat";
import {
  LegalModal,
  type LegalDocument,
} from "@/components/home/LegalModal";
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
const MODAL_CLOSE_ANIMATION_MS = 160;
function isHomeLanguage(value: string | null): value is HomeLanguage {
  return value === "english" || value === "french" || value === "arabic";
}

function isDisconnectedExtensionMessageError(reason: unknown) {
  const message =
    reason instanceof Error
      ? reason.message
      : typeof reason === "string"
        ? reason
        : "";

  return message.includes(
    "Could not establish connection. Receiving end does not exist.",
  );
}

function ChatIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-7 w-7 text-[#f5dfad]"
      fill="none"
      viewBox="0 0 24 24"
    >
      <path
        d="M5 5h14v10H9l-4 4V5Z"
        fill="currentColor"
        opacity="0.9"
      />
      <path
        d="M8 8.5h8M8 11.5h5"
        stroke="#050302"
        strokeLinecap="square"
        strokeWidth="2"
      />
    </svg>
  );
}

export function HomeView() {
  const [showAuthModal, setShowAuthModal] = useState(false);
  const [isAuthModalClosing, setIsAuthModalClosing] = useState(false);
  const [showMobileChat, setShowMobileChat] = useState(false);
  const [showProfileModal, setShowProfileModal] = useState(false);
  const [isProfileModalClosing, setIsProfileModalClosing] = useState(false);
  const [legalDocument, setLegalDocument] = useState<LegalDocument | null>(
    null,
  );
  const [isLegalModalClosing, setIsLegalModalClosing] = useState(false);
  const [language, setLanguage] = useState<HomeLanguage>("english");
  const translations = homeTranslations[language];
  const openProfileAfterMatch = useCallback(() => {
    setIsProfileModalClosing(false);
    setShowProfileModal(true);
  }, []);
  const {
    chatCooldownSeconds,
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
  const handleGameFrameRef = useCallback(
    (frame: HTMLIFrameElement | null) => {
      // Keep the controller pointed at the active iframe window.
      registerGameWindow(frame?.contentWindow ?? null);
    },
    [registerGameWindow],
  );

  useEffect(() => {
    const savedLanguage = window.localStorage.getItem(LANGUAGE_STORAGE_KEY);

    if (isHomeLanguage(savedLanguage)) {
      // Defer localStorage state so server and first client render use the same language.
      window.setTimeout(() => setLanguage(savedLanguage), 0);
    }
  }, []);

  useEffect(() => {
    window.localStorage.setItem(LANGUAGE_STORAGE_KEY, language);
  }, [language]);

  useEffect(() => {
    function suppressDisconnectedExtensionMessage(
      event: PromiseRejectionEvent,
    ) {
      if (isDisconnectedExtensionMessageError(event.reason)) {
        event.preventDefault();
      }
    }

    window.addEventListener(
      "unhandledrejection",
      suppressDisconnectedExtensionMessage,
    );

    return () => {
      window.removeEventListener(
        "unhandledrejection",
        suppressDisconnectedExtensionMessage,
      );
    };
  }, []);

  function handlePlayGame() {
    setShowMobileChat(false);
    setShowProfileModal(false);
    setIsProfileModalClosing(false);
    playGame();
  }

  function openAuthModal() {
    setIsAuthModalClosing(false);
    setShowAuthModal(true);
  }

  const closeAuthModal = useCallback(() => {
    if (isAuthModalClosing) {
      return;
    }

    setIsAuthModalClosing(true);
    window.setTimeout(() => {
      setShowAuthModal(false);
      setIsAuthModalClosing(false);
    }, MODAL_CLOSE_ANIMATION_MS);
  }, [isAuthModalClosing]);

  function openProfileModal() {
    if (!isPlayerProfileLoading && !needsUsernameSetup) {
      setIsProfileModalClosing(false);
      setShowProfileModal(true);
    }
  }

  const closeProfileModal = useCallback(() => {
    if (isProfileModalClosing) {
      return;
    }

    setIsProfileModalClosing(true);
    window.setTimeout(() => {
      setShowProfileModal(false);
      setIsProfileModalClosing(false);
    }, MODAL_CLOSE_ANIMATION_MS);
  }, [isProfileModalClosing]);

  function openLegalModal(document: LegalDocument) {
    setIsLegalModalClosing(false);
    setLegalDocument(document);
  }

  const closeLegalModal = useCallback(() => {
    if (isLegalModalClosing || legalDocument === null) {
      return;
    }

    setIsLegalModalClosing(true);
    window.setTimeout(() => {
      setLegalDocument(null);
      setIsLegalModalClosing(false);
    }, MODAL_CLOSE_ANIMATION_MS);
  }, [isLegalModalClosing, legalDocument]);

  useEffect(() => {
    function handleEscapeKey(event: KeyboardEvent) {
      if (event.key !== "Escape") {
        return;
      }

      if (legalDocument !== null) {
        event.preventDefault();
        closeLegalModal();
        return;
      }

      if (showAuthModal) {
        event.preventDefault();
        closeAuthModal();
        return;
      }

      if (showProfileModal && !showGame) {
        event.preventDefault();
        closeProfileModal();
        return;
      }

      if (showMobileChat) {
        event.preventDefault();
        setShowMobileChat(false);
      }
    }

    window.addEventListener("keydown", handleEscapeKey);

    return () => {
      window.removeEventListener("keydown", handleEscapeKey);
    };
  }, [
    closeAuthModal,
    closeLegalModal,
    closeProfileModal,
    legalDocument,
    showAuthModal,
    showGame,
    showMobileChat,
    showProfileModal,
  ]);

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
        <div className={showMobileChat ? "hidden lg:contents" : "contents"}>
        <TopBarActions
          className="absolute left-3 right-3 top-3 justify-end sm:left-auto sm:right-6 sm:top-6 lg:hidden"
          language={language}
          onLanguageChange={setLanguage}
          onProfileClick={openProfileModal}
          playerProfile={playerProfile}
          translations={{
            ...translations.fullscreen,
            ...translations.language,
            profile: translations.profile.profile,
          }}
        />
        </div>
      )}

      {!showGame && (
        <div className={showMobileChat ? "hidden lg:contents" : "contents"}>
          <div className="absolute inset-0 z-10 flex items-center justify-center px-4 py-20 max-[760px]:py-16 max-[520px]:py-14">
            <div
              className="flex w-full max-w-[38rem] -translate-x-7 flex-col items-center gap-5 sm:gap-6 max-[760px]:gap-4 max-[520px]:gap-3 xl:translate-y-[clamp(-11.25rem,calc((48rem-100vh)*0.55),0rem)]"
              dir="ltr"
            >
                <div className="flex flex-col items-center gap-4 text-center max-[760px]:gap-3 max-[520px]:gap-2">
                  <Image
                    src="/images/icon.png"
                    alt="Pixel Fight icon"
                    width={112}
                    height={112}
                    priority
                    className="h-24 w-24 animate-[float_3s_ease-in-out_infinite] drop-shadow-[0_6px_0_rgba(5,3,2,0.65)] [image-rendering:pixelated] sm:h-28 sm:w-28 max-[760px]:h-20 max-[760px]:w-20 max-[520px]:h-16 max-[520px]:w-16"
                  />
                  <div className="flex flex-col items-center gap-2">
                    <h1 className="pixel-title-font text-4xl font-bold uppercase leading-none tracking-[0.08em] text-[#f5dfad] [text-shadow:0_4px_0_#050302,4px_0_0_#050302,0_-4px_0_#050302,-4px_0_0_#050302,4px_4px_0_#050302] min-[360px]:text-5xl sm:text-7xl max-[760px]:text-5xl max-[520px]:text-4xl">
                      PIXEL FIGHT
                    </h1>
                    <div className="flex w-full items-center justify-center gap-3">
                      <span className="h-[3px] w-12 bg-[#f5dfad]/40 shadow-[0_1px_0_#050302]" />
                      <span className="text-xs font-bold uppercase tracking-[0.35em] text-[#f5dfad]/80 [text-shadow:0_2px_0_#050302] sm:text-sm max-[520px]:tracking-[0.22em]">
                        {translations.home.battleArena}
                      </span>
                      <span className="h-[3px] w-12 bg-[#f5dfad]/40 shadow-[0_1px_0_#050302]" />
                    </div>
                    <span className="text-[10px] font-bold uppercase tracking-[0.22em] text-[#f5dfad]/65 [text-shadow:0_2px_0_#050302] sm:text-xs">
                      v2.0.3
                    </span>
                    <div className="flex flex-col items-center gap-1 text-[9px] uppercase tracking-[0.12em] sm:text-[10px]">
                      <a
                        className="text-[#e2b84f] underline decoration-[#e2b84f]/60 underline-offset-4 hover:text-[#f5dfad] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#e2b84f]"
                        href="#terms-of-service"
                        onClick={(event) => {
                          event.preventDefault();
                          openLegalModal("terms");
                        }}
                      >
                        {translations.legal.termsOfService}
                      </a>
                      <a
                        className="text-[#e2b84f] underline decoration-[#e2b84f]/60 underline-offset-4 hover:text-[#f5dfad] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#e2b84f]"
                        href="#privacy-policy"
                        onClick={(event) => {
                          event.preventDefault();
                          openLegalModal("privacy");
                        }}
                      >
                        {translations.legal.privacyPolicy}
                      </a>
                    </div>
                  </div>
                </div>

                <div className="flex h-[12.5rem] w-full flex-col items-center gap-3 max-[760px]:gap-2">
                  <div className="flex h-[5.25rem] w-[20rem] max-w-full items-center justify-center">
                    {isPlayerProfileLoading ? (
                      <div className="flex h-[4.75rem] min-w-[12rem] items-center justify-center bg-[#151819] px-6 text-sm uppercase text-[#f5dfad] shadow-[0_0_0_3px_#050302,0_4px_0_3px_#111515,inset_0_3px_0_#374041,inset_0_-3px_0_#050302]">
                        {translations.home.loading}
                      </div>
                    ) : (
                      <PlayButton
                        disabled={!gameUrl || needsUsernameSetup}
                        label={translations.home.play}
                        onClick={handlePlayGame}
                      />
                    )}
                  </div>

                  <div className="flex h-10 items-center justify-center">
                    <OnlinePlayersBadge
                      label={translations.home.online}
                      onlineCount={onlineCount}
                    />
                  </div>

                  <div
                    className={`flex h-10 translate-y-2 items-start justify-center ${
                      playerProfile?.isGuest ? "" : "invisible pointer-events-none"
                    }`}
                    aria-hidden={!playerProfile?.isGuest}
                  >
                    {playerProfile?.isGuest && (
                      <LoginSignupButton
                        label={translations.home.loginSignup}
                        onClick={openAuthModal}
                      />
                    )}
                  </div>
                </div>
            </div>
          </div>

          <div className="absolute left-[calc(50%+12rem)] top-1/2 z-20 hidden w-[21rem] -translate-y-[68%] flex-col items-stretch gap-4 min-[1220px]:flex min-[1440px]:left-[calc(50%+15rem)] min-[1440px]:w-[28em]">
                <TopBarActions
                  className="justify-start"
                  language={language}
                  onLanguageChange={setLanguage}
                  onProfileClick={openProfileModal}
                  playerProfile={playerProfile}
                  translations={{
                    ...translations.fullscreen,
                    ...translations.language,
                    profile: translations.profile.profile,
                  }}
                />
                <GlobalChat
                  className="w-full min-w-0"
                  closeLabel={translations.chat.close}
                  cooldownSeconds={chatCooldownSeconds}
                  errorMessage={chatError?.message ?? null}
                  isConnected={isChatConnected}
                  messages={chatMessages}
                  onSendMessage={sendChatMessage}
                  playerProfile={playerProfile}
                  style={{ height: "min(27rem, calc(100vh - 11rem))" }}
                  textDirection={language === "arabic" ? "rtl" : "ltr"}
                  title={translations.chat.title}
                  translations={translations.chat}
                />
          </div>
        </div>
      )}

      {!showGame && !showMobileChat && (
        <button
          aria-label={translations.chat.open}
          className="absolute bottom-4 right-4 z-30 flex h-14 min-w-14 items-center justify-center gap-2 bg-[#212627] px-3 shadow-[0_0_0_3px_#050302,0_4px_0_3px_#111515,inset_0_3px_0_#374041,inset_0_-3px_0_#151819] hover:brightness-110 active:translate-y-1 active:shadow-[0_0_0_3px_#050302,0_1px_0_3px_#111515,inset_0_2px_0_#374041,inset_0_-2px_0_#151819] sm:bottom-6 sm:right-6 min-[1220px]:hidden"
          onClick={() => setShowMobileChat(true)}
          title={translations.chat.open}
          type="button"
        >
          <ChatIcon />
          <span className="hidden text-xs uppercase text-[#d9b46b] min-[360px]:block">
            {translations.chat.open}
          </span>
        </button>
      )}

      {!showGame && showMobileChat && (
        <div className="absolute inset-0 z-40 flex bg-black/90 p-3 sm:p-5 min-[1220px]:hidden">
          <GlobalChat
            className="h-full w-full min-w-0"
            closeLabel={translations.chat.close}
            cooldownSeconds={chatCooldownSeconds}
            errorMessage={chatError?.message ?? null}
            isConnected={isChatConnected}
            messages={chatMessages}
            onClose={() => setShowMobileChat(false)}
            onSendMessage={sendChatMessage}
            playerProfile={playerProfile}
            style={{ height: "100%" }}
            textDirection={language === "arabic" ? "rtl" : "ltr"}
            title={translations.chat.title}
            translations={translations.chat}
          />
        </div>
      )}

      {showAuthModal && (
        <AuthModal
          isClosing={isAuthModalClosing}
          onClose={closeAuthModal}
          translations={translations.auth}
        />
      )}
      {showProfileModal && !showGame && (
        <ProfileModal
          key={playerProfile?.playerId ?? "loading"}
          isClosing={isProfileModalClosing}
          onClose={closeProfileModal}
          onDeleteAccount={deleteAccount}
          onLogout={signOut}
          onProgressAnimationSeen={clearMatchProgressAnimation}
          onProfileUpdated={refreshPlayerProfile}
          playerProfile={playerProfile}
          progressAnimation={matchProgressAnimation}
          translations={translations.profile}
        />
      )}
      {legalDocument !== null && !showGame && (
        <LegalModal
          document={legalDocument}
          isClosing={isLegalModalClosing}
          onClose={closeLegalModal}
          translations={translations.legal}
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
          ref={handleGameFrameRef}
          src={gameUrl}
          allow="fullscreen"
          className={`absolute inset-0 z-20 h-full w-full border-0 ${
            showGame ? "visible" : "invisible pointer-events-none"
          }`}
        />
      )}
    </main>
  );
}
