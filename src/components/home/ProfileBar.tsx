"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { getPixelAvatarDataUri } from "@/components/home/pixelAvatar";
import type { PlayerProfile } from "@/models/player/playerProfile.model";
import type {
  HomeLanguage,
  HomeTranslations,
} from "@/views/home/homeTranslations";

type ProfileBarProps = {
  language: HomeLanguage;
  onLanguageChange: (language: HomeLanguage) => void;
  onLoginClick: () => void;
  onProfileClick: () => void;
  playerProfile: PlayerProfile | null;
  translations: HomeTranslations["language"] & {
    login: string;
    profile: string;
  };
};

const brickWallStyle = {
  backgroundColor: "#212627",
  backgroundImage:
    "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='72' height='36' viewBox='0 0 72 36'%3E%3Crect width='72' height='36' fill='%23151819'/%3E%3Crect x='2' y='2' width='32' height='14' fill='%23212627'/%3E%3Crect x='36' y='2' width='34' height='14' fill='%23252b2c'/%3E%3Crect x='2' y='20' width='16' height='14' fill='%23252b2c'/%3E%3Crect x='20' y='20' width='32' height='14' fill='%23212627'/%3E%3Crect x='54' y='20' width='16' height='14' fill='%231f2425'/%3E%3Crect x='5' y='4' width='24' height='2' fill='%23374041' opacity='.55'/%3E%3Crect x='40' y='4' width='18' height='2' fill='%23374041' opacity='.45'/%3E%3Crect x='24' y='22' width='20' height='2' fill='%23374041' opacity='.5'/%3E%3Crect x='7' y='13' width='8' height='2' fill='%23050302' opacity='.22'/%3E%3Crect x='60' y='11' width='6' height='2' fill='%23050302' opacity='.2'/%3E%3Crect x='41' y='30' width='8' height='2' fill='%23050302' opacity='.2'/%3E%3C/svg%3E\")",
  backgroundSize: "60px 30px",
};

const ICON_BUTTON_BASE =
  "flex h-10 w-10 items-center justify-center bg-[#151819] shadow-[inset_0_2px_0_#374041,inset_0_-2px_0_#050302] transition-[transform,filter] hover:brightness-110 active:translate-y-[1px]";

const ICON_BUTTON_ACTIVE =
  "bg-[#6c4724] shadow-[inset_0_2px_0_#8a6034,inset_0_-2px_0_#2b160d]";

function ProfileIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-5 w-5 text-[#f5dfad]"
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

function LoginIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-5 w-5 text-[#d7ffb8]"
      fill="none"
      viewBox="0 0 24 24"
    >
      <path
        d="M14 4h5v16h-5"
        stroke="currentColor"
        strokeLinejoin="round"
        strokeWidth="1.8"
      />
      <path
        d="M3 12h11M10 8l4 4-4 4"
        stroke="currentColor"
        strokeLinecap="square"
        strokeLinejoin="round"
        strokeWidth="1.8"
      />
    </svg>
  );
}

function LanguageIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-5 w-5 text-[#f5dfad]"
      fill="none"
      viewBox="0 0 24 24"
    >
      <path
        d="M3.5 12a8.5 8.5 0 1 0 17 0 8.5 8.5 0 0 0-17 0Z"
        stroke="currentColor"
        strokeWidth="1.7"
      />
      <path
        d="M4.5 9h15M4.5 15h15M12 3.5c2 2.25 3 5.08 3 8.5s-1 6.25-3 8.5M12 3.5c-2 2.25-3 5.08-3 8.5s1 6.25 3 8.5"
        stroke="currentColor"
        strokeLinecap="square"
        strokeWidth="1.4"
      />
    </svg>
  );
}

export function ProfileBar({
  language,
  onLanguageChange,
  onLoginClick,
  onProfileClick,
  playerProfile,
  translations,
}: ProfileBarProps) {
  const [showLanguageMenu, setShowLanguageMenu] = useState(false);
  const languageMenuRef = useRef<HTMLDivElement>(null);
  const playerName = playerProfile?.playerName ?? "Player";
  const customAvatarUrl = playerProfile?.isGuest
    ? undefined
    : playerProfile?.avatarUrl;
  const avatarSeed = playerProfile?.playerId ?? playerName;
  const pixelAvatarDataUri = useMemo(
    () => getPixelAvatarDataUri(avatarSeed),
    [avatarSeed],
  );
  const avatarImage = customAvatarUrl ?? pixelAvatarDataUri;
  const isGuest = playerProfile?.isGuest ?? false;
  const languageOptions: HomeLanguage[] = ["english", "french", "arabic"];

  useEffect(() => {
    if (!showLanguageMenu) {
      return;
    }

    function handlePointerDown(event: PointerEvent) {
      if (
        event.target instanceof Node &&
        languageMenuRef.current?.contains(event.target)
      ) {
        return;
      }

      setShowLanguageMenu(false);
    }

    document.addEventListener("pointerdown", handlePointerDown);

    return () => {
      document.removeEventListener("pointerdown", handlePointerDown);
    };
  }, [showLanguageMenu]);

  return (
    <div
      className="flex w-[min(26rem,calc(100vw-2rem))] items-center gap-2 px-3 py-2 shadow-[0_0_0_3px_#050302,0_4px_0_3px_#111515,inset_0_3px_0_#374041,inset_0_-3px_0_#151819]"
      style={brickWallStyle}
    >
      <div className="flex min-w-0 flex-1 items-center gap-2.5">
        <span
          aria-label={`${playerName} avatar`}
          className="flex h-10 w-10 shrink-0 items-center justify-center overflow-hidden bg-[#1c2e1a] shadow-[inset_0_2px_0_#374041,inset_0_-2px_0_#050302] [image-rendering:pixelated]"
          role="img"
          style={{
            backgroundImage: `url("${avatarImage}")`,
            backgroundSize: "cover",
            backgroundPosition: "center",
          }}
        />
        <span className="min-w-0 truncate text-[13px] uppercase tracking-wide text-[#f5dfad]">
          {playerName}
        </span>
      </div>

      <div className="flex items-center gap-1.5">
        <button
          aria-label={translations.profile}
          className={ICON_BUTTON_BASE}
          onClick={onProfileClick}
          type="button"
        >
          <ProfileIcon />
        </button>

        {isGuest && (
          <button
            aria-label={translations.login}
            className={ICON_BUTTON_BASE}
            onClick={onLoginClick}
            type="button"
          >
            <LoginIcon />
          </button>
        )}

        <div className="relative" ref={languageMenuRef}>
          <button
            aria-expanded={showLanguageMenu}
            aria-label={translations.label}
            className={`${ICON_BUTTON_BASE} ${
              showLanguageMenu ? ICON_BUTTON_ACTIVE : ""
            }`}
            onClick={() =>
              setShowLanguageMenu((currentValue) => !currentValue)
            }
            type="button"
          >
            <LanguageIcon />
          </button>
          {showLanguageMenu && (
            <div
              className="absolute right-0 top-[2.75rem] z-40 flex w-32 flex-col gap-1 bg-[#151819] p-2 shadow-[0_0_0_3px_#050302,0_4px_0_3px_#111515,inset_0_2px_0_#374041,inset_0_-2px_0_#050302]"
              role="menu"
            >
              {languageOptions.map((languageOption) => (
                <button
                  className={`px-3 py-2 text-left text-xs uppercase shadow-[inset_0_2px_0_#374041,inset_0_-2px_0_#151819] hover:bg-[#2a3031] ${
                    languageOption === language
                      ? "bg-[#2a3031] text-[#f5dfad]"
                      : "bg-[#212627] text-[#d9b46b]"
                  }`}
                  key={languageOption}
                  onClick={() => {
                    onLanguageChange(languageOption);
                    setShowLanguageMenu(false);
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
    </div>
  );
}
