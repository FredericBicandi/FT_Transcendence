import { FormEvent, useMemo, useState } from "react";
import type { DashboardChatMessage } from "@/controllers/home/useDashboardSocket";
import type { PlayerProfile } from "@/models/player/playerProfile.model";
import type { HomeTranslations } from "@/views/home/homeTranslations";

type GlobalChatProps = {
  errorMessage: string | null;
  isConnected: boolean;
  messages: DashboardChatMessage[];
  onSendMessage: (content: string, playerProfile: PlayerProfile) => boolean;
  playerProfile: PlayerProfile | null;
  textDirection: "ltr" | "rtl";
  translations: HomeTranslations["chat"];
};

const usernameColors = [
  "#f5dfad",
  "#d9b46b",
  "#7dd3fc",
  "#86efac",
  "#fca5a5",
  "#c4b5fd",
  "#f9a8d4",
  "#fde047",
];

function getUsernameColor(username: string) {
  let hash = 0;

  // Keep a player's chat color stable without storing extra data.
  for (let index = 0; index < username.length; index += 1) {
    hash = (hash + username.charCodeAt(index) * (index + 1)) % 997;
  }

  return usernameColors[hash % usernameColors.length];
}

function formatSentAt(sentAt: string) {
  const date = new Date(sentAt);

  if (Number.isNaN(date.getTime())) {
    return "";
  }

  return new Intl.DateTimeFormat("en-US", {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(date);
}

function isRtlMessage(content: string) {
  return /[\u0591-\u08FF\uFB1D-\uFDFD\uFE70-\uFEFC]/.test(content);
}

export function GlobalChat({
  errorMessage,
  isConnected,
  messages,
  onSendMessage,
  playerProfile,
  textDirection,
  translations,
}: GlobalChatProps) {
  const [draftMessage, setDraftMessage] = useState("");
  const isAuthenticated = playerProfile ? !playerProfile.isGuest : false;
  const canSendMessages = isAuthenticated && isConnected;
  const coloredMessages = useMemo(
    () =>
      messages.map((message) => ({
        ...message,
        sentAtLabel: formatSentAt(message.sentAt),
        usernameColor: getUsernameColor(message.playerName),
        isRtl: isRtlMessage(message.content),
      })),
    [messages],
  );

  function sendMessage(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!canSendMessages || !playerProfile) {
      return;
    }

    const text = draftMessage.trim();

    if (!text) {
      return;
    }

    if (onSendMessage(text, playerProfile)) {
      setDraftMessage("");
    }
  }

  function updateDraftMessage(value: string) {
    // Count real characters, not UTF-16 units, so Arabic/emoji behave better.
    setDraftMessage(Array.from(value).slice(0, 140).join(""));
  }

  return (
    <section
      className="chat-font hidden w-[28rem] flex-col bg-black/55 shadow-[0_0_0_3px_#050302,0_4px_0_3px_rgba(0,0,0,0.55),inset_0_3px_0_rgba(255,255,255,0.08)] backdrop-blur-[2px] lg:flex"
      dir={textDirection}
      style={{ height: "28rem" }}
    >
      <div className="flex-1 overflow-y-auto px-4 py-3 text-xs leading-6 [scrollbar-color:#b8893b_rgba(0,0,0,0.35)]">
        {coloredMessages.map((message) => (
          <div
            key={message.messageId}
            className="flex w-full min-w-0 flex-nowrap gap-2 text-[#f5dfad]/90"
            dir={message.isRtl ? "rtl" : "ltr"}
          >
            {message.isRtl ? (
              <>
                <span className="min-w-0 flex-1 text-right [unicode-bidi:plaintext]">
                  {message.content}
                </span>
                <span
                  className="shrink-0 [unicode-bidi:isolate]"
                  style={{ color: message.usernameColor }}
                >
                  {message.playerName}:
                </span>
                <span className="shrink-0 text-[#d9b46b]/80 [unicode-bidi:isolate]">
                  {message.sentAtLabel}
                </span>
              </>
            ) : (
              <>
                <span className="shrink-0 text-[#d9b46b]/80 [unicode-bidi:isolate]">
                  {message.sentAtLabel}
                </span>
                <span
                  className="shrink-0 [unicode-bidi:isolate]"
                  style={{ color: message.usernameColor }}
                >
                  {message.playerName}:
                </span>
                <span className="min-w-0 flex-1 text-left [unicode-bidi:plaintext]">
                  {message.content}
                </span>
              </>
            )}
          </div>
        ))}
      </div>

      <form
        className="border-t border-[#b8893b]/45 bg-[#050302]/60 px-3 py-3"
        onSubmit={sendMessage}
      >
        <input
          aria-label={translations.inputLabel}
          className="h-9 w-full bg-[#212627]/85 px-3 text-xs text-[#f5dfad] outline-none shadow-[inset_0_2px_0_#374041,inset_0_-2px_0_#151819] placeholder:text-[#d9b46b]/55 disabled:cursor-not-allowed disabled:text-[#d9b46b]/70 focus:shadow-[0_0_0_2px_#b8893b,inset_0_2px_0_#374041,inset_0_-2px_0_#151819]"
          disabled={!canSendMessages}
          onChange={(event) => updateDraftMessage(event.target.value)}
          placeholder={
            !isAuthenticated
              ? translations.signInToSend
              : isConnected
                ? translations.placeholder
                : translations.unavailable
          }
          value={draftMessage}
        />
        {errorMessage && (
          <p className="mt-2 text-[10px] text-[#fca5a5]">{errorMessage}</p>
        )}
      </form>
    </section>
  );
}
