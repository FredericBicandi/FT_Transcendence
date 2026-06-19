import { FormEvent, useMemo, useState } from "react";
import type { DashboardChatMessage } from "@/controllers/home/useDashboardSocket";
import type { PlayerProfile } from "@/models/player/playerProfile.model";
import type { HomeTranslations } from "@/views/home/homeTranslations";

type GlobalChatProps = {
  cooldownSeconds: number;
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
  cooldownSeconds,
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
  const isCoolingDown = cooldownSeconds > 0;
  const canSendMessages = isAuthenticated && isConnected && !isCoolingDown;
  const cooldownMessage = translations.cooldown.replace(
    "{seconds}",
    String(cooldownSeconds),
  );
  const isRtlLayout = textDirection === "rtl";
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
      style={{ height: "27rem" }}
    >
      <div
        className="flex-1 overflow-y-auto px-4 py-3 text-xs leading-6 [scrollbar-color:#b8893b_rgba(0,0,0,0.35)]"
        dir="ltr"
      >
        {coloredMessages.map((message) => (
          <div
            key={message.messageId}
            className={`grid w-full min-w-0 items-start gap-2 text-[#f5dfad]/90 ${
              isRtlLayout
                ? "grid-cols-[minmax(0,1fr)_max-content_3.25rem]"
                : "grid-cols-[3.25rem_max-content_minmax(0,1fr)]"
            }`}
          >
            {isRtlLayout ? (
              <>
                <span
                  className={`min-w-0 break-words [unicode-bidi:plaintext] ${
                    message.isRtl ? "text-right" : "text-left"
                  }`}
                  dir={message.isRtl ? "rtl" : "ltr"}
                >
                  {message.content}
                </span>
                <span
                  className="whitespace-nowrap text-right [unicode-bidi:isolate]"
                  dir="rtl"
                  style={{ color: message.usernameColor }}
                >
                  :{message.playerName}
                </span>
                <span
                  className="text-right text-[#d9b46b]/80 [font-variant-numeric:tabular-nums] [unicode-bidi:isolate]"
                  dir="ltr"
                >
                  {message.sentAtLabel}
                </span>
              </>
            ) : (
              <>
                <span className="text-[#d9b46b]/80 [font-variant-numeric:tabular-nums] [unicode-bidi:isolate]">
                  {message.sentAtLabel}
                </span>
                <span
                  className="whitespace-nowrap [unicode-bidi:isolate]"
                  style={{ color: message.usernameColor }}
                >
                  {message.playerName}:
                </span>
                <span
                  className={`min-w-0 break-words [unicode-bidi:plaintext] ${
                    message.isRtl ? "text-right" : "text-left"
                  }`}
                  dir={message.isRtl ? "rtl" : "ltr"}
                >
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
              : isCoolingDown
                ? cooldownMessage
              : isConnected
                ? translations.placeholder
                : translations.unavailable
          }
          value={draftMessage}
        />
        {(isCoolingDown || errorMessage) && (
          <p className="mt-2 text-[10px] text-[#fca5a5]">
            {isCoolingDown ? cooldownMessage : errorMessage}
          </p>
        )}
      </form>
    </section>
  );
}
