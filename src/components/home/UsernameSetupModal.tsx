// UsernameSetupModal blocks authenticated players until their required profile username is saved.
// It communicates with playerProfile.model and HomeView's profile refresh callback.
// Do not casually bypass this gate; the game URL depends on a resolved player name.

import { FormEvent, useState } from "react";
import {
  isUsernameTakenError,
  saveAuthenticatedPlayerProfile,
  type PlayerProfile,
} from "@/models/player/playerProfile.model";
import type { HomeTranslations } from "@/views/home/homeTranslations";

type UsernameSetupModalProps = {
  onProfileUpdated: () => Promise<void>;
  playerProfile: PlayerProfile;
  translations: HomeTranslations["profile"];
};

export function UsernameSetupModal({
  onProfileUpdated,
  playerProfile,
  translations,
}: UsernameSetupModalProps) {
  const [playerName, setPlayerName] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  async function saveUsername(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const normalizedPlayerName = playerName.trim();

    if (!normalizedPlayerName) {
      setErrorMessage(translations.usernameRequired);
      return;
    }

    setIsSaving(true);
    setErrorMessage(null);

    try {
      // Force authenticated players to pick a real username before playing.
      await saveAuthenticatedPlayerProfile({
        avatarUrl: playerProfile.avatarUrl,
        playerId: playerProfile.playerId,
        playerName: normalizedPlayerName,
      });
      await onProfileUpdated();
    } catch (error) {
      setErrorMessage(
        isUsernameTakenError(error)
          ? translations.usernameTaken
          : translations.saveFailed,
      );
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <div className="absolute inset-0 z-50 flex items-center justify-center bg-black/45 px-4 backdrop-blur-[2px]">
      <form
        className="flex w-[min(24rem,calc(100vw-2rem))] flex-col gap-6 bg-[#212627]/95 px-7 py-9 shadow-[0_0_0_4px_#050302,0_8px_0_4px_#111515,inset_0_4px_0_#374041,inset_0_-4px_0_#151819]"
        onSubmit={saveUsername}
      >
        <h2 className="text-center text-xl uppercase text-[#f5dfad]">
          {translations.chooseUsername}
        </h2>

        <label className="flex h-14 items-center bg-[#151819] px-4 shadow-[inset_0_3px_0_#050302,inset_0_-3px_0_#374041] focus-within:shadow-[0_0_0_2px_#b8893b,inset_0_3px_0_#050302,inset_0_-3px_0_#374041]">
          <input
            aria-label={translations.usernameInput}
            autoFocus
            className="min-w-0 flex-1 bg-transparent text-base uppercase text-[#f5dfad] outline-none placeholder:text-[#d9b46b]/55"
            maxLength={18}
            onChange={(event) => {
              setErrorMessage(null);
              setPlayerName(event.target.value);
            }}
            placeholder={translations.usernameInput}
            value={playerName}
          />
        </label>

        {errorMessage && (
          <p className="text-center text-sm uppercase text-[#d9b46b]">
            {errorMessage}
          </p>
        )}

        <button
          className="h-12 bg-[#344326] text-lg uppercase text-[#d9b46b] shadow-[0_0_0_3px_#050302,0_4px_0_3px_#172111,inset_0_3px_0_#53663a,inset_0_-3px_0_#202b17] hover:bg-[#40522d] hover:text-[#ead08a] active:translate-y-1 active:shadow-[0_0_0_3px_#050302,0_1px_0_3px_#172111,inset_0_2px_0_#53663a,inset_0_-2px_0_#202b17] disabled:cursor-not-allowed disabled:bg-[#303536] disabled:text-[#8a8170] disabled:shadow-[0_0_0_3px_#050302,0_4px_0_3px_#151819,inset_0_3px_0_#4a5051,inset_0_-3px_0_#202425]"
          disabled={isSaving}
          type="submit"
        >
          {isSaving ? translations.applying : translations.confirm}
        </button>
      </form>
    </div>
  );
}
