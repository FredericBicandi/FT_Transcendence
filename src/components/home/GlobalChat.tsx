import type { CSSProperties } from "react";
import { FormEvent, useLayoutEffect, useMemo, useRef, useState } from "react";
import type { DashboardChatMessage } from "@/controllers/home/useDashboardSocket";
import type { PlayerProfile } from "@/models/player/playerProfile.model";
import type { HomeTranslations } from "@/views/home/homeTranslations";

type GlobalChatProps = {
  className?: string;
  closeLabel?: string;
  cooldownSeconds: number;
  errorMessage: string | null;
  isConnected: boolean;
  messages: DashboardChatMessage[];
  onClose?: () => void;
  onSendMessage: (content: string, playerProfile: PlayerProfile) => boolean;
  playerProfile: PlayerProfile | null;
  style?: CSSProperties;
  textDirection: "ltr" | "rtl";
  title?: string;
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
  className,
  closeLabel,
  cooldownSeconds,
  errorMessage,
  isConnected,
  messages,
  onClose,
  onSendMessage,
  playerProfile,
  style,
  textDirection,
  title,
  translations,
}: GlobalChatProps) {
  const [draftMessage, setDraftMessage] = useState("");
  const messagesContainerRef = useRef<HTMLDivElement>(null);
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

  useLayoutEffect(() => {
    const messagesContainer = messagesContainerRef.current;

    if (!messagesContainer) {
      return;
    }

    messagesContainer.scrollTop = messagesContainer.scrollHeight;
  }, [coloredMessages.length]);

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
      className={`chat-font flex min-h-0 flex-col bg-black/55 shadow-[0_0_0_3px_#050302,0_4px_0_3px_rgba(0,0,0,0.55),inset_0_3px_0_rgba(255,255,255,0.08)] backdrop-blur-[2px] ${
        className ?? "w-[28rem]"
      }`}
      dir={textDirection}
      style={style ?? { height: "27rem" }}
    >
      {onClose && (
        <div className="flex min-h-14 items-center justify-between border-b border-[#b8893b]/45 bg-[#050302]/75 px-3">
          <h2 className="truncate text-sm uppercase tracking-[0.08em] text-[#f5dfad]">
            {title ?? "Global Chat"}
          </h2>
          <button
            aria-label={closeLabel ?? "Close global chat"}
            className="flex h-10 w-10 items-center justify-center bg-[#212627] text-lg uppercase text-[#f5dfad] shadow-[0_0_0_2px_#050302,0_3px_0_2px_#111515,inset_0_2px_0_#374041,inset_0_-2px_0_#151819] hover:brightness-110 active:translate-y-1 active:shadow-[0_0_0_2px_#050302,0_1px_0_2px_#111515,inset_0_1px_0_#374041,inset_0_-1px_0_#151819]"
            onClick={onClose}
            title={closeLabel ?? "Close global chat"}
            type="button"
          >
            X
          </button>
        </div>
      )}

      <div
        className="min-h-0 flex-1 overflow-y-auto px-3 py-3 text-xs leading-6 [scrollbar-color:#b8893b_rgba(0,0,0,0.35)] sm:px-4"
        dir="ltr"
        ref={messagesContainerRef}
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
                  className="max-w-[5.5rem] truncate whitespace-nowrap text-left [unicode-bidi:isolate] sm:max-w-[7rem]"
                  dir="ltr"
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
                  className="max-w-[5.5rem] truncate whitespace-nowrap [unicode-bidi:isolate] sm:max-w-[7rem]"
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
