import { ChangeEvent, useEffect, useState } from "react";
import {
  isUsernameTakenError,
  saveAuthenticatedPlayerProfile,
  type MatchProgressUpdate,
  type PlayerProfile,
} from "@/models/player/playerProfile.model";
import type { HomeTranslations } from "@/views/home/homeTranslations";

type ProfileModalProps = {
  onClose: () => void;
  onDeleteAccount: () => Promise<void>;
  onLogout: () => Promise<void>;
  onProgressAnimationSeen?: () => void;
  onProfileUpdated: () => Promise<void>;
  playerProfile: PlayerProfile | null;
  progressAnimation?: (MatchProgressUpdate & { id: number }) | null;
  translations: HomeTranslations["profile"];
};

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

function LockIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-5 w-5"
      fill="none"
      viewBox="0 0 24 24"
    >
      <path
        d="M7 10V8a5 5 0 0 1 10 0v2"
        stroke="currentColor"
        strokeLinecap="square"
        strokeWidth="2"
      />
      <path
        d="M5 10h14v10H5V10Z"
        stroke="currentColor"
        strokeLinejoin="round"
        strokeWidth="2"
      />
      <path
        d="M12 14v3"
        stroke="currentColor"
        strokeLinecap="square"
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
  onDeleteAccount,
  onLogout,
  onProgressAnimationSeen,
  onProfileUpdated,
  playerProfile,
  progressAnimation,
  translations,
}: ProfileModalProps) {
  const [playerName, setPlayerName] = useState(
    playerProfile?.playerName ?? "Player",
  );
  const [avatarPreviewUrl, setAvatarPreviewUrl] = useState<string | undefined>(
    playerProfile?.isGuest ? undefined : playerProfile?.avatarUrl,
  );
  const [avatarDataUrl, setAvatarDataUrl] = useState<string | undefined>();
  const [saveStatus, setSaveStatus] = useState<string | null>(null);
  const [isDeletingAccount, setIsDeletingAccount] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [progressAnimationToPlay] = useState(progressAnimation ?? null);
  const isAuthenticatedPlayer = playerProfile ? !playerProfile.isGuest : false;
  const normalizedPlayerName = playerName.trim();
  const hasPlayerNameChanged =
    normalizedPlayerName !== (playerProfile?.playerName.trim() ?? "");
  const hasAvatarChanged = avatarDataUrl !== undefined;
  const hasProfileChanges = hasPlayerNameChanged || hasAvatarChanged;
  const [displayedProgress, setDisplayedProgress] = useState(() => ({
    currentXp: playerProfile?.currentXp ?? 0,
    level: playerProfile?.level ?? 0,
    xpRequiredForNextLevel:
      playerProfile?.xpRequiredForNextLevel ?? 100,
  }));
  const activeProgress = progressAnimationToPlay
    ? displayedProgress
    : {
        currentXp: playerProfile?.currentXp ?? 0,
        level: playerProfile?.level ?? 0,
        xpRequiredForNextLevel:
          playerProfile?.xpRequiredForNextLevel ?? 100,
      };
  const level = activeProgress.level;
  const xpRequiredForNextLevel = Math.max(
    1,
    activeProgress.xpRequiredForNextLevel,
  );
  const expPercent = Math.min(
    100,
    Math.round((activeProgress.currentXp / xpRequiredForNextLevel) * 100),
  );
  const matchLogs = playerProfile?.matchLogs ?? [];

  useEffect(() => {
    if (!progressAnimationToPlay) {
      return;
    }

    const animation = progressAnimationToPlay;
    onProgressAnimationSeen?.();

    type ProgressSegment = {
      durationMs: number;
      endXp: number;
      level: number;
      startXp: number;
      xpRequiredForNextLevel: number;
    };

    function getXpRequiredForAnimatedLevel(level: number) {
      if (level === animation.previousLevel) {
        return animation.previousXpRequiredForNextLevel;
      }

      if (level >= animation.level) {
        return animation.xpRequiredForNextLevel;
      }

      return (
        animation.previousXpRequiredForNextLevel +
        (level - animation.previousLevel) * 100
      );
    }

    const segments: ProgressSegment[] = [];
    let animatedLevel = animation.previousLevel;
    let animatedXp = animation.previousCurrentXp;
    let remainingXp = animation.xpGained;

    while (remainingXp > 0) {
      const xpRequiredForNextLevel = Math.max(
        1,
        getXpRequiredForAnimatedLevel(animatedLevel),
      );
      const xpUntilNextLevel = Math.max(0, xpRequiredForNextLevel - animatedXp);
      const segmentXp = Math.min(remainingXp, xpUntilNextLevel || remainingXp);
      const endXp = Math.min(xpRequiredForNextLevel, animatedXp + segmentXp);

      segments.push({
        durationMs: Math.min(1400, Math.max(480, segmentXp * 8)),
        endXp,
        level: animatedLevel,
        startXp: animatedXp,
        xpRequiredForNextLevel,
      });

      remainingXp -= segmentXp;

      if (endXp < xpRequiredForNextLevel || remainingXp <= 0) {
        animatedXp = endXp;
        break;
      }

      animatedLevel += 1;
      animatedXp = 0;
    }

    if (segments.length === 0) {
      segments.push({
        durationMs: 480,
        endXp: animation.currentXp,
        level: animation.level,
        startXp: animation.previousCurrentXp,
        xpRequiredForNextLevel: animation.xpRequiredForNextLevel,
      });
    }

    let animationFrameId = 0;
    let segmentIndex = 0;
    let segmentStartedAt: number | null = null;

    function animateFrame(timestamp: number) {
      const segment = segments[segmentIndex];

      if (!segment) {
        setDisplayedProgress({
          currentXp: animation.currentXp,
          level: animation.level,
          xpRequiredForNextLevel: animation.xpRequiredForNextLevel,
        });
        return;
      }

      if (segmentStartedAt === null) {
        segmentStartedAt = timestamp;
      }

      const progress = Math.min(
        1,
        (timestamp - segmentStartedAt) / segment.durationMs,
      );
      const easedProgress = 1 - Math.pow(1 - progress, 3);
      const currentXp = Math.round(
        segment.startXp +
          (segment.endXp - segment.startXp) * easedProgress,
      );

      setDisplayedProgress({
        currentXp,
        level: segment.level,
        xpRequiredForNextLevel: segment.xpRequiredForNextLevel,
      });

      if (progress < 1) {
        animationFrameId = window.requestAnimationFrame(animateFrame);
        return;
      }

      segmentIndex += 1;
      segmentStartedAt = null;

      if (segments[segmentIndex]) {
        setDisplayedProgress({
          currentXp: 0,
          level: segments[segmentIndex].level,
          xpRequiredForNextLevel:
            segments[segmentIndex].xpRequiredForNextLevel,
        });
        animationFrameId = window.requestAnimationFrame(animateFrame);
        return;
      }

      setDisplayedProgress({
        currentXp: animation.currentXp,
        level: animation.level,
        xpRequiredForNextLevel: animation.xpRequiredForNextLevel,
      });
    }

    animationFrameId = window.requestAnimationFrame(animateFrame);

    return () => {
      window.cancelAnimationFrame(animationFrameId);
    };
  }, [onProgressAnimationSeen, progressAnimationToPlay]);

  useEffect(() => {
    return () => {
      if (avatarPreviewUrl?.startsWith("blob:")) {
        URL.revokeObjectURL(avatarPreviewUrl);
      }
    };
  }, [avatarPreviewUrl]);

  function changeAvatar(event: ChangeEvent<HTMLInputElement>) {
    if (!isAuthenticatedPlayer) {
      event.target.value = "";
      return;
    }

    const file = event.target.files?.[0];

    if (!file) {
      return;
    }

    setSaveStatus(null);
    setAvatarPreviewUrl((currentUrl) => {
      if (currentUrl?.startsWith("blob:")) {
        URL.revokeObjectURL(currentUrl);
      }

      return URL.createObjectURL(file);
    });

    const reader = new FileReader();
    reader.onload = () => {
      if (typeof reader.result === "string") {
        setAvatarDataUrl(reader.result);
      }
    };
    reader.readAsDataURL(file);
  }

  async function applyProfileChanges() {
    if (
      !playerProfile ||
      !isAuthenticatedPlayer ||
      !normalizedPlayerName ||
      !hasProfileChanges ||
      isSaving
    ) {
      return;
    }

    setIsSaving(true);
    setSaveStatus(null);

    try {
      await saveAuthenticatedPlayerProfile({
        avatarUrl: avatarDataUrl ?? playerProfile?.avatarUrl,
        playerId: playerProfile.playerId,
        playerName: normalizedPlayerName,
      });

      await onProfileUpdated();
      setAvatarDataUrl(undefined);
      setSaveStatus(translations.saveSuccess);
    } catch (error) {
      setSaveStatus(
        isUsernameTakenError(error)
          ? translations.usernameTaken
          : translations.saveFailed,
      );
    } finally {
      setIsSaving(false);
    }
  }

  async function logout() {
    await onLogout();
    onClose();
  }

  async function deleteAccount() {
    if (
      !isAuthenticatedPlayer ||
      isDeletingAccount ||
      !window.confirm(translations.deleteAccountConfirm)
    ) {
      return;
    }

    setIsDeletingAccount(true);
    setSaveStatus(null);

    try {
      await onDeleteAccount();
      onClose();
    } catch {
      setSaveStatus(translations.saveFailed);
    } finally {
      setIsDeletingAccount(false);
    }
  }

  return (
    <div
      className="absolute inset-0 z-40 flex items-center justify-center bg-black/35 px-4 backdrop-blur-[2px]"
      onClick={onClose}
    >
      <section
        className="relative grid max-h-[calc(100vh-3rem)] w-[min(70rem,calc(100vw-2rem))] grid-cols-1 gap-8 overflow-y-auto px-7 py-14 shadow-[0_0_0_4px_#050302,0_8px_0_4px_#111515,inset_0_4px_0_#374041,inset_0_-4px_0_#151819] md:grid-cols-[20rem_minmax(0,1fr)] md:px-9"
        onClick={(event) => event.stopPropagation()}
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

          <label className={`group relative flex h-40 w-40 items-center justify-center overflow-hidden bg-[#151819] shadow-[0_0_0_3px_#050302,inset_0_4px_0_#374041,inset_0_-4px_0_#050302] ${isAuthenticatedPlayer ? "cursor-pointer" : "cursor-not-allowed opacity-80"}`}>
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
              {isAuthenticatedPlayer ? <PencilIcon /> : <LockIcon />}
            </span>
            <input
              accept="image/*"
              aria-label={translations.photoInput}
              className="sr-only"
              disabled={!isAuthenticatedPlayer}
              onChange={changeAvatar}
              type="file"
            />
          </label>

          <label className={`flex h-14 w-full max-w-sm items-center gap-3 bg-[#151819] px-4 text-[#d9b46b] shadow-[inset_0_3px_0_#050302,inset_0_-3px_0_#374041] ${isAuthenticatedPlayer ? "focus-within:shadow-[0_0_0_2px_#b8893b,inset_0_3px_0_#050302,inset_0_-3px_0_#374041]" : "cursor-not-allowed opacity-80"}`}>
            {isAuthenticatedPlayer ? <PencilIcon /> : <LockIcon />}
            <input
              aria-label={translations.usernameInput}
              className="min-w-0 flex-1 bg-transparent text-base uppercase text-[#f5dfad] outline-none disabled:cursor-not-allowed disabled:text-[#d9b46b]/70"
              disabled={!isAuthenticatedPlayer}
              maxLength={18}
              onChange={(event) => {
                setSaveStatus(null);
                setPlayerName(event.target.value);
              }}
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
              {activeProgress.currentXp} / {xpRequiredForNextLevel}
            </span>
          </div>

          <button
            className="h-12 w-full max-w-sm bg-[#344326] text-lg uppercase text-[#d9b46b] shadow-[0_0_0_3px_#050302,0_4px_0_3px_#172111,inset_0_3px_0_#53663a,inset_0_-3px_0_#202b17] hover:bg-[#40522d] hover:text-[#ead08a] active:translate-y-1 active:shadow-[0_0_0_3px_#050302,0_1px_0_3px_#172111,inset_0_2px_0_#53663a,inset_0_-2px_0_#202b17] disabled:cursor-not-allowed disabled:bg-[#303536] disabled:text-[#8a8170] disabled:shadow-[0_0_0_3px_#050302,0_4px_0_3px_#151819,inset_0_3px_0_#4a5051,inset_0_-3px_0_#202425] disabled:hover:bg-[#303536] disabled:hover:text-[#8a8170] disabled:active:translate-y-0"
            disabled={
              !isAuthenticatedPlayer ||
              !normalizedPlayerName ||
              !hasProfileChanges ||
              isSaving
            }
            onClick={applyProfileChanges}
            type="button"
          >
            {isSaving ? translations.applying : translations.apply}
          </button>

          {saveStatus && (
            <p className="text-center text-sm uppercase text-[#d9b46b]">
              {saveStatus}
            </p>
          )}

          {isAuthenticatedPlayer && (
            <div className="flex w-full max-w-sm flex-col gap-3">
              <button
                className="h-10 w-full bg-[#151819] text-sm uppercase text-[#f5dfad] shadow-[0_0_0_2px_#050302,inset_0_2px_0_#374041,inset_0_-2px_0_#050302] hover:bg-[#2a3031] active:translate-y-0.5 disabled:cursor-not-allowed disabled:text-[#8a8170]"
                disabled={isDeletingAccount}
                onClick={logout}
                type="button"
              >
                {translations.logout}
              </button>
              <button
                className="h-10 w-full bg-[#4b2323] text-sm uppercase text-[#f5dfad] shadow-[0_0_0_2px_#050302,inset_0_2px_0_#7a3434,inset_0_-2px_0_#250f0f] hover:bg-[#653030] active:translate-y-0.5 disabled:cursor-not-allowed disabled:bg-[#303536] disabled:text-[#8a8170] disabled:active:translate-y-0"
                disabled={isDeletingAccount}
                onClick={deleteAccount}
                type="button"
              >
                {isDeletingAccount
                  ? translations.deletingAccount
                  : translations.deleteAccount}
              </button>
            </div>
          )}
        </div>

        <div className="flex min-h-[24rem] flex-col gap-5">
          <div className="flex items-center gap-3">
            <MatchLogIcon />
            <h2 className="text-2xl uppercase text-[#f5dfad]">
              {translations.matchLog}
            </h2>
          </div>

          <div className="flex min-h-0 flex-1 flex-col overflow-x-auto overflow-y-hidden bg-[#151819] shadow-[0_0_0_3px_#050302,inset_0_3px_0_#374041,inset_0_-3px_0_#050302] [scrollbar-color:#b8893b_rgba(0,0,0,0.35)]">
            <div className="grid min-w-[38rem] grid-cols-[1.35fr_0.85fr_0.65fr_0.65fr_0.75fr] bg-black/35 px-5 py-4 text-base uppercase text-[#d9b46b]">
              <span>{translations.dateTime}</span>
              <span>{translations.playTime}</span>
              <span>{translations.kills}</span>
              <span>{translations.death}</span>
              <span>{translations.score}</span>
            </div>
            <div className="min-w-[38rem] flex-1 overflow-y-auto [scrollbar-color:#b8893b_rgba(0,0,0,0.35)]">
              {isAuthenticatedPlayer && matchLogs.length > 0 ? (
                matchLogs.map((matchLog) => (
                  <div
                    className="grid min-h-16 grid-cols-[1.35fr_0.85fr_0.65fr_0.65fr_0.75fr] items-center px-5 py-4 text-base text-[#f5dfad] odd:bg-[#212627]/55 even:bg-[#1b2021]/55"
                    key={matchLog.id}
                  >
                    <span>{matchLog.playedAt}</span>
                    <span>{matchLog.playTime}</span>
                    <span>{matchLog.kills}</span>
                    <span>{matchLog.deaths}</span>
                    <span>{matchLog.score}</span>
                  </div>
                ))
              ) : isAuthenticatedPlayer ? (
                <div className="flex min-h-64 items-center justify-center px-5 py-8 text-center text-base uppercase text-[#d9b46b]">
                  {translations.noMatchLogs}
                </div>
              ) : (
                <div className="flex min-h-64 items-center justify-center px-5 py-8 text-center text-base uppercase text-[#d9b46b]">
                  {translations.signInToSaveMatchLogs}
                </div>
              )}
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
