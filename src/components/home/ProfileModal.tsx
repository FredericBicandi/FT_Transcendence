import { ChangeEvent, useEffect, useState } from "react";
import type { PlayerProfile } from "@/models/player/playerProfile.model";
import type { HomeTranslations } from "@/views/home/homeTranslations";

type ProfileModalProps = {
  onClose: () => void;
  playerProfile: PlayerProfile | null;
  translations: HomeTranslations["profile"];
};

const matchLogs = [
  {
    playedAt: "05/19 14:27",
    kills: 12,
    deaths: 4,
    score: 2180,
  },
  {
    playedAt: "05/19 13:52",
    kills: 7,
    deaths: 6,
    score: 1435,
  },
  {
    playedAt: "05/18 21:10",
    kills: 18,
    deaths: 3,
    score: 3120,
  },
  {
    playedAt: "05/18 20:34",
    kills: 5,
    deaths: 8,
    score: 980,
  },
];

const brickWallStyle = {
  backgroundColor: "rgba(33, 38, 39, 0.68)",
  backgroundImage:
    "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='72' height='36' viewBox='0 0 72 36'%3E%3Crect width='72' height='36' fill='%23151819' fill-opacity='.62'/%3E%3Crect x='2' y='2' width='32' height='14' fill='%23212627' fill-opacity='.62'/%3E%3Crect x='36' y='2' width='34' height='14' fill='%23252b2c' fill-opacity='.62'/%3E%3Crect x='2' y='20' width='16' height='14' fill='%23252b2c' fill-opacity='.62'/%3E%3Crect x='20' y='20' width='32' height='14' fill='%23212627' fill-opacity='.62'/%3E%3Crect x='54' y='20' width='16' height='14' fill='%231f2425' fill-opacity='.62'/%3E%3Crect x='5' y='4' width='24' height='2' fill='%23374041' opacity='.38'/%3E%3Crect x='40' y='4' width='18' height='2' fill='%23374041' opacity='.32'/%3E%3Crect x='24' y='22' width='20' height='2' fill='%23374041' opacity='.34'/%3E%3Crect x='7' y='13' width='8' height='2' fill='%23050302' opacity='.16'/%3E%3Crect x='60' y='11' width='6' height='2' fill='%23050302' opacity='.14'/%3E%3Crect x='41' y='30' width='8' height='2' fill='%23050302' opacity='.14'/%3E%3C/svg%3E\")",
  backgroundSize: "72px 36px",
};

function AvatarIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-16 w-16 text-[#f5dfad]"
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

function CloseIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-5 w-5"
      fill="none"
      viewBox="0 0 24 24"
    >
      <path
        d="M6 6l12 12M18 6 6 18"
        stroke="currentColor"
        strokeLinecap="square"
        strokeWidth="3"
      />
    </svg>
  );
}

function PencilIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-5 w-5"
      fill="none"
      viewBox="0 0 24 24"
    >
      <path
        d="m5 16-.8 3.8L8 19l10.8-10.8-3-3L5 16Z"
        stroke="currentColor"
        strokeLinejoin="round"
        strokeWidth="2"
      />
      <path
        d="m14.5 6.5 3 3"
        stroke="currentColor"
        strokeWidth="2"
      />
    </svg>
  );
}

function MatchLogIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-6 w-6 text-[#d9b46b]"
      fill="none"
      viewBox="0 0 24 24"
    >
      <path
        d="M6 4h12v16H6V4Z"
        stroke="currentColor"
        strokeLinejoin="round"
        strokeWidth="2"
      />
      <path
        d="M9 8h6M9 12h6M9 16h4"
        stroke="currentColor"
        strokeLinecap="square"
        strokeWidth="2"
      />
    </svg>
  );
}

export function ProfileModal({
  onClose,
  playerProfile,
  translations,
}: ProfileModalProps) {
  const [playerName, setPlayerName] = useState(
    playerProfile?.playerName ?? "Player",
  );
  const [avatarPreviewUrl, setAvatarPreviewUrl] = useState<string | undefined>(
    playerProfile?.isGuest ? undefined : playerProfile?.avatarUrl,
  );
  const level = playerProfile?.level ?? 0;
  const expPercent = 64;

  useEffect(() => {
    return () => {
      if (avatarPreviewUrl?.startsWith("blob:")) {
        URL.revokeObjectURL(avatarPreviewUrl);
      }
    };
  }, [avatarPreviewUrl]);

  function changeAvatar(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];

    if (!file) {
      return;
    }

    setAvatarPreviewUrl((currentUrl) => {
      if (currentUrl?.startsWith("blob:")) {
        URL.revokeObjectURL(currentUrl);
      }

      return URL.createObjectURL(file);
    });
  }

  return (
    <div className="absolute inset-0 z-40 flex items-center justify-center bg-black/35 px-4 backdrop-blur-[2px]">
      <section
        className="relative grid max-h-[calc(100vh-3rem)] w-[min(58rem,calc(100vw-2rem))] grid-cols-1 gap-8 overflow-y-auto px-7 py-14 shadow-[0_0_0_4px_#050302,0_8px_0_4px_#111515,inset_0_4px_0_#374041,inset_0_-4px_0_#151819] md:grid-cols-[0.9fr_1.1fr] md:px-9"
        style={brickWallStyle}
      >
        <button
          aria-label={translations.close}
          className="absolute left-3 top-3 flex h-9 w-9 items-center justify-center bg-[#151819] text-[#f5dfad] shadow-[0_0_0_2px_#050302,inset_0_2px_0_#374041,inset_0_-2px_0_#050302] hover:bg-[#2a3031] hover:text-[#ead7a6] active:translate-y-0.5"
          onClick={onClose}
          type="button"
        >
          <CloseIcon />
        </button>

        <div className="flex flex-col items-center justify-center gap-7">
          <div className="flex items-end gap-3">
            <span className="text-base uppercase text-[#d9b46b]">
              {translations.level}
            </span>
            <span className="text-4xl leading-none text-[#f5dfad]">
              {level}
            </span>
          </div>

          <label className="group relative flex h-40 w-40 cursor-pointer items-center justify-center overflow-hidden bg-[#151819] shadow-[0_0_0_3px_#050302,inset_0_4px_0_#374041,inset_0_-4px_0_#050302]">
            {avatarPreviewUrl ? (
              <span
                aria-hidden="true"
                className="h-full w-full bg-cover bg-center"
                style={{ backgroundImage: `url("${avatarPreviewUrl}")` }}
              />
            ) : (
              <AvatarIcon />
            )}
            <span className="absolute inset-0 hidden items-center justify-center bg-black/55 text-[#f5dfad] group-hover:flex">
              <PencilIcon />
            </span>
            <input
              accept="image/*"
              aria-label={translations.photoInput}
              className="sr-only"
              onChange={changeAvatar}
              type="file"
            />
          </label>

          <label className="flex h-14 w-full max-w-sm items-center gap-3 bg-[#151819] px-4 shadow-[inset_0_3px_0_#050302,inset_0_-3px_0_#374041] focus-within:shadow-[0_0_0_2px_#b8893b,inset_0_3px_0_#050302,inset_0_-3px_0_#374041]">
            <PencilIcon />
            <input
              aria-label={translations.usernameInput}
              className="min-w-0 flex-1 bg-transparent text-base uppercase text-[#f5dfad] outline-none"
              maxLength={18}
              onChange={(event) => setPlayerName(event.target.value)}
              value={playerName}
            />
          </label>

          <div className="grid w-full max-w-sm grid-cols-[auto_1fr] items-center gap-x-4 gap-y-2">
            <span className="text-base uppercase text-[#d9b46b]">
              {translations.exp}
            </span>
            <div className="h-5 bg-[#151819] shadow-[inset_0_2px_0_#050302,inset_0_-2px_0_#374041]">
              <div
                className="h-full bg-[#344326] shadow-[inset_0_2px_0_#53663a,inset_0_-2px_0_#202b17]"
                style={{ width: `${expPercent}%` }}
              />
            </div>
            <span className="col-start-2 text-right text-sm text-[#f5dfad]">
              {expPercent}%
            </span>
          </div>

          <button
            className="h-12 w-full max-w-sm bg-[#344326] text-lg uppercase text-[#d9b46b] shadow-[0_0_0_3px_#050302,0_4px_0_3px_#172111,inset_0_3px_0_#53663a,inset_0_-3px_0_#202b17] hover:bg-[#40522d] hover:text-[#ead08a] active:translate-y-1 active:shadow-[0_0_0_3px_#050302,0_1px_0_3px_#172111,inset_0_2px_0_#53663a,inset_0_-2px_0_#202b17]"
            type="button"
          >
            Apply
          </button>
        </div>

        <div className="flex min-h-[24rem] flex-col gap-5">
          <div className="flex items-center gap-3">
            <MatchLogIcon />
            <h2 className="text-2xl uppercase text-[#f5dfad]">
              {translations.matchLog}
            </h2>
          </div>

          <div className="flex min-h-0 flex-1 flex-col overflow-hidden bg-[#151819] shadow-[0_0_0_3px_#050302,inset_0_3px_0_#374041,inset_0_-3px_0_#050302]">
            <div className="grid grid-cols-[1.4fr_repeat(3,0.65fr)] bg-black/35 px-5 py-4 text-base uppercase text-[#d9b46b]">
              <span>{translations.dateTime}</span>
              <span>{translations.kills}</span>
              <span>{translations.death}</span>
              <span>{translations.score}</span>
            </div>
            <div className="flex-1 overflow-y-auto [scrollbar-color:#b8893b_rgba(0,0,0,0.35)]">
              {matchLogs.map((matchLog) => (
                <div
                  className="grid min-h-16 grid-cols-[1.4fr_repeat(3,0.65fr)] items-center px-5 py-4 text-base text-[#f5dfad] odd:bg-[#212627]/55 even:bg-[#1b2021]/55"
                  key={matchLog.playedAt}
                >
                  <span>{matchLog.playedAt}</span>
                  <span>{matchLog.kills}</span>
                  <span>{matchLog.deaths}</span>
                  <span>{matchLog.score}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
