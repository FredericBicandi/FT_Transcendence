import { useCallback, useEffect, useRef, useState } from "react";
import type { PlayerProfile } from "@/models/player/playerProfile.model";
import type {
  HomeLanguage,
  HomeTranslations,
} from "@/views/home/homeTranslations";

type TopBarActionsProps = {
  className?: string;
  language: HomeLanguage;
  onProfileClick: () => void;
  onLanguageChange: (language: HomeLanguage) => void;
  playerProfile: PlayerProfile | null;
  translations: HomeTranslations["language"] &
    HomeTranslations["fullscreen"] & {
      profile: string;
    };
};

const brickWallStyle = {
  backgroundColor: "#212627",
  backgroundImage:
    "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='72' height='36' viewBox='0 0 72 36'%3E%3Crect width='72' height='36' fill='%23151819'/%3E%3Crect x='2' y='2' width='32' height='14' fill='%23212627'/%3E%3Crect x='36' y='2' width='34' height='14' fill='%23252b2c'/%3E%3Crect x='2' y='20' width='16' height='14' fill='%23252b2c'/%3E%3Crect x='20' y='20' width='32' height='14' fill='%23212627'/%3E%3Crect x='54' y='20' width='16' height='14' fill='%231f2425'/%3E%3Crect x='5' y='4' width='24' height='2' fill='%23374041' opacity='.55'/%3E%3Crect x='40' y='4' width='18' height='2' fill='%23374041' opacity='.45'/%3E%3Crect x='24' y='22' width='20' height='2' fill='%23374041' opacity='.5'/%3E%3Crect x='7' y='13' width='8' height='2' fill='%23050302' opacity='.22'/%3E%3Crect x='60' y='11' width='6' height='2' fill='%23050302' opacity='.2'/%3E%3Crect x='41' y='30' width='8' height='2' fill='%23050302' opacity='.2'/%3E%3C/svg%3E\")",
  backgroundSize: "72px 36px",
};

const LANGUAGE_MENU_ANIMATION_MS = 140;

type FullscreenDocument = Document & {
  webkitFullscreenElement?: Element | null;
  mozFullScreenElement?: Element | null;
  msFullscreenElement?: Element | null;
  webkitExitFullscreen?: () => Promise<void> | void;
  mozCancelFullScreen?: () => Promise<void> | void;
  msExitFullscreen?: () => Promise<void> | void;
};

type FullscreenElement = HTMLElement & {
  webkitRequestFullscreen?: () => Promise<void> | void;
  mozRequestFullScreen?: () => Promise<void> | void;
  msRequestFullscreen?: () => Promise<void> | void;
};

function getFullscreenElement() {
  const fullscreenDocument = document as FullscreenDocument;

  return (
    document.fullscreenElement ??
    fullscreenDocument.webkitFullscreenElement ??
    fullscreenDocument.mozFullScreenElement ??
    fullscreenDocument.msFullscreenElement ??
    null
  );
}

async function requestFullscreen(element: FullscreenElement) {
  const request =
    element.requestFullscreen ??
    element.webkitRequestFullscreen ??
    element.mozRequestFullScreen ??
    element.msRequestFullscreen;

  await request?.call(element);
}

async function exitFullscreen() {
  const fullscreenDocument = document as FullscreenDocument;
  const exit =
    document.exitFullscreen ??
    fullscreenDocument.webkitExitFullscreen ??
    fullscreenDocument.mozCancelFullScreen ??
    fullscreenDocument.msExitFullscreen;

  await exit?.call(document);
}

function AvatarIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-6 w-6 text-[#f5dfad]"
      fill="none"
      viewBox="0 0 24 24"
    >
      <path
        d="M12 12.5c2.21 0 4-1.9 4-4.25S14.21 4 12 4 8 5.9 8 8.25s1.79 4.25 4 4.25Z"
        fill="currentColor"
      />
      <path
        d="M5 20c.7-3.34 3.3-5.25 7-5.25s6.3 1.91 7 5.25H5Z"
        fill="currentColor"
      />
    </svg>
  );
}

function LanguageIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-7 w-7 text-[#f5dfad]"
      fill="none"
      viewBox="0 0 24 24"
    >
      <path
        d="M3.5 12a8.5 8.5 0 1 0 17 0 8.5 8.5 0 0 0-17 0Z"
        stroke="currentColor"
        strokeWidth="2"
      />
      <path
        d="M4.5 9h15M4.5 15h15M12 3.5c2 2.25 3 5.08 3 8.5s-1 6.25-3 8.5M12 3.5c-2 2.25-3 5.08-3 8.5s1 6.25 3 8.5"
        stroke="currentColor"
        strokeLinecap="square"
        strokeWidth="1.8"
      />
      <path
        d="M17.5 18.5h3M19 15.5v6M16.6 21.5l2.4-6 2.4 6"
        stroke="#d9b46b"
        strokeLinecap="square"
        strokeLinejoin="round"
        strokeWidth="2"
      />
    </svg>
  );
}

function FullscreenIcon({ isFullscreen }: { isFullscreen: boolean }) {
  return (
    <svg
      aria-hidden="true"
      className="h-7 w-7 text-[#f5dfad]"
      fill="none"
      viewBox="0 0 24 24"
    >
      {isFullscreen ? (
        <path
          d="M9 4v5H4M15 4v5h5M9 20v-5H4M15 20v-5h5"
          stroke="currentColor"
          strokeLinecap="square"
          strokeLinejoin="round"
          strokeWidth="2.2"
        />
      ) : (
        <path
          d="M9 4H4v5M15 4h5v5M9 20H4v-5M15 20h5v-5"
          stroke="currentColor"
          strokeLinecap="square"
          strokeLinejoin="round"
          strokeWidth="2.2"
        />
      )}
    </svg>
  );
}

export function TopBarActions({
  className,
  language,
  onLanguageChange,
  onProfileClick,
  playerProfile,
  translations,
}: TopBarActionsProps) {
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [showLanguageMenu, setShowLanguageMenu] = useState(false);
  const [renderLanguageMenu, setRenderLanguageMenu] = useState(false);
  const languageMenuRef = useRef<HTMLDivElement>(null);
  const playerName = playerProfile?.playerName ?? "Player";
  const avatarUrl = playerProfile?.isGuest ? undefined : playerProfile?.avatarUrl;
  const languageOptions: HomeLanguage[] = ["english", "french", "arabic"];
  const toggleFullscreen = useCallback(async () => {
    try {
      if (getFullscreenElement()) {
        await exitFullscreen();
      } else {
        await requestFullscreen(document.documentElement);
      }

      setIsFullscreen(getFullscreenElement() !== null);
    } catch {
      // Fullscreen can be unavailable or blocked by browser policy.
    }
  }, []);

  useEffect(() => {
    function updateFullscreenState() {
      setIsFullscreen(getFullscreenElement() !== null);
    }

    updateFullscreenState();
    document.addEventListener("fullscreenchange", updateFullscreenState);
    document.addEventListener("webkitfullscreenchange", updateFullscreenState);
    document.addEventListener("mozfullscreenchange", updateFullscreenState);
    document.addEventListener("MSFullscreenChange", updateFullscreenState);

    return () => {
      document.removeEventListener("fullscreenchange", updateFullscreenState);
      document.removeEventListener(
        "webkitfullscreenchange",
        updateFullscreenState,
      );
      document.removeEventListener("mozfullscreenchange", updateFullscreenState);
      document.removeEventListener("MSFullscreenChange", updateFullscreenState);
    };
  }, []);

  useEffect(() => {
    function handleFullscreenKey(event: KeyboardEvent) {
      if (event.key !== "F11") {
        return;
      }

      event.preventDefault();
      void toggleFullscreen();
    }

    window.addEventListener("keydown", handleFullscreenKey, true);

    return () => {
      window.removeEventListener("keydown", handleFullscreenKey, true);
    };
  }, [toggleFullscreen]);

  useEffect(() => {
    if (!showLanguageMenu) {
      return;
    }

    function handlePointerDown(event: PointerEvent) {
      // Close the menu when the user clicks outside it.
      if (
        event.target instanceof Node &&
        languageMenuRef.current?.contains(event.target)
      ) {
        return;
      }

      closeLanguageMenu();
    }

    document.addEventListener("pointerdown", handlePointerDown);

    return () => {
      document.removeEventListener("pointerdown", handlePointerDown);
    };
  }, [showLanguageMenu]);

  useEffect(() => {
    if (showLanguageMenu || !renderLanguageMenu) {
      return;
    }

    const closeTimer = window.setTimeout(() => {
      setRenderLanguageMenu(false);
    }, LANGUAGE_MENU_ANIMATION_MS);

    return () => {
      window.clearTimeout(closeTimer);
    };
  }, [renderLanguageMenu, showLanguageMenu]);

  function closeLanguageMenu() {
    setShowLanguageMenu(false);
  }

  function toggleLanguageMenu() {
    setRenderLanguageMenu(true);
    setShowLanguageMenu((currentValue) => !currentValue);
  }

  return (
    <div
      className={`z-30 flex items-start gap-2 sm:gap-3 ${
        className ?? "absolute right-4 top-4 sm:right-6 sm:top-6"
      }`}
      dir="ltr"
    >
      <button
        aria-label={isFullscreen ? translations.exit : translations.enter}
        aria-pressed={isFullscreen}
        className="flex h-14 min-w-14 flex-col items-center justify-center gap-1 px-2 shadow-[0_0_0_3px_#050302,0_4px_0_3px_#111515,inset_0_3px_0_#374041,inset_0_-3px_0_#151819] hover:brightness-110 hover:shadow-[0_0_0_3px_#050302,0_4px_0_3px_#111515,inset_0_3px_0_#465253,inset_0_-3px_0_#151819] active:translate-y-1 active:shadow-[0_0_0_3px_#050302,0_1px_0_3px_#111515,inset_0_2px_0_#374041,inset_0_-2px_0_#151819] sm:h-16 sm:min-w-24 sm:px-3"
        onClick={toggleFullscreen}
        style={brickWallStyle}
        title={isFullscreen ? translations.exit : translations.enter}
        type="button"
      >
        <FullscreenIcon isFullscreen={isFullscreen} />
        <span className="hidden max-w-28 text-center text-xs uppercase leading-tight text-[#d9b46b] sm:block">
          {isFullscreen ? translations.exit : translations.enter}
        </span>
      </button>

      <button
        aria-label={translations.profile}
        className="grid h-14 min-w-14 grid-cols-[40px] items-center justify-center px-2 py-2 text-left shadow-[0_0_0_3px_#050302,0_4px_0_3px_#111515,inset_0_3px_0_#374041,inset_0_-3px_0_#151819] hover:brightness-110 hover:shadow-[0_0_0_3px_#050302,0_4px_0_3px_#111515,inset_0_3px_0_#465253,inset_0_-3px_0_#151819] active:translate-y-1 active:shadow-[0_0_0_3px_#050302,0_1px_0_3px_#111515,inset_0_2px_0_#374041,inset_0_-2px_0_#151819] sm:min-h-16 sm:min-w-58 sm:grid-cols-[48px_minmax(0,1fr)] sm:grid-rows-2 sm:justify-stretch sm:px-3"
        onClick={onProfileClick}
        style={brickWallStyle}
        title={translations.profile}
        type="button"
      >
        <span className="row-span-2 flex h-10 w-10 items-center justify-center overflow-hidden bg-[#151819] shadow-[inset_0_2px_0_#374041,inset_0_-2px_0_#050302]">
          {avatarUrl ? (
            <span
              aria-hidden="true"
              className="h-full w-full bg-cover bg-center"
              style={{ backgroundImage: `url("${avatarUrl}")` }}
            />
          ) : (
            <AvatarIcon />
          )}
        </span>
        <span className="hidden truncate text-sm uppercase text-[#f5dfad] sm:block">
          {playerName}
        </span>
        <span className="hidden text-xs uppercase text-[#d9b46b] sm:block">
          {translations.profile}
        </span>
      </button>

      <div className="relative" ref={languageMenuRef}>
        <button
          aria-expanded={showLanguageMenu}
          aria-label={translations.label}
          className="flex h-14 min-w-14 flex-col items-center justify-center gap-1 px-2 shadow-[0_0_0_3px_#050302,0_4px_0_3px_#111515,inset_0_3px_0_#374041,inset_0_-3px_0_#151819] hover:brightness-110 hover:shadow-[0_0_0_3px_#050302,0_4px_0_3px_#111515,inset_0_3px_0_#465253,inset_0_-3px_0_#151819] active:translate-y-1 active:shadow-[0_0_0_3px_#050302,0_1px_0_3px_#111515,inset_0_2px_0_#374041,inset_0_-2px_0_#151819] sm:h-16 sm:min-w-24 sm:px-3"
          onClick={toggleLanguageMenu}
          style={brickWallStyle}
          type="button"
        >
          <LanguageIcon />
          <span className="hidden text-xs text-[#d9b46b] sm:block">
            {translations.options[language]}
          </span>
        </button>

        {renderLanguageMenu && (
          <div
            className={`absolute right-0 top-[4.75rem] flex w-32 flex-col gap-1 bg-[#151819] p-2 shadow-[0_0_0_3px_#050302,0_4px_0_3px_#111515,inset_0_2px_0_#374041,inset_0_-2px_0_#050302] ${
              showLanguageMenu
                ? "menu-fade-down-enter"
                : "menu-fade-up-exit pointer-events-none"
            }`}
            role="menu"
          >
            {languageOptions.map((languageOption) => (
              <button
                className="bg-[#212627] px-3 py-2 text-left text-xs uppercase text-[#f5dfad] shadow-[inset_0_2px_0_#374041,inset_0_-2px_0_#151819] hover:bg-[#2a3031]"
                key={languageOption}
                onClick={() => {
                  onLanguageChange(languageOption);
                  closeLanguageMenu();
                }}
                role="menuitem"
                type="button"
              >
                {translations.options[languageOption]}
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
