import { FormEvent, useMemo, useState } from "react";
import type { PlayerProfile } from "@/models/player/playerProfile.model";
import type { HomeTranslations } from "@/views/home/homeTranslations";

type ChatMessage = {
  id: string;
  sentAt: string;
  username: string;
  text: string;
};

type GlobalChatProps = {
  playerProfile: PlayerProfile | null;
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

const dummyMessages: ChatMessage[] = [
  {
    id: "dummy-1",
    sentAt: "14:19",
    username: "MossKnight",
    text: "mid bridge is clear",
  },
  {
    id: "dummy-2",
    sentAt: "14:21",
    username: "Guest4821",
    text: "need backup near spawn",
  },
  {
    id: "dummy-3",
    sentAt: "14:24",
    username: "PixelMage",
    text: "holding top wall",
  },
  {
    id: "dummy-4",
    sentAt: "14:27",
    username: "MossKnight",
    text: "two players coming right side",
  },
  {
    id: "dummy-5",
    sentAt: "14:28",
    username: "StoneRunner",
    text: "got it",
  },
];

function getUsernameColor(username: string) {
  let hash = 0;

  for (let index = 0; index < username.length; index += 1) {
    hash = (hash + username.charCodeAt(index) * (index + 1)) % 997;
  }

  return usernameColors[hash % usernameColors.length];
}

function getCurrentTime() {
  return new Intl.DateTimeFormat("en-US", {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(new Date());
}

export function GlobalChat({
  playerProfile,
  translations,
}: GlobalChatProps) {
  const [messages, setMessages] = useState(dummyMessages);
  const [draftMessage, setDraftMessage] = useState("");
  const canSendMessages = playerProfile ? !playerProfile.isGuest : false;
  const playerName = playerProfile?.playerName ?? "Player";
  const coloredMessages = useMemo(
    () =>
      messages.map((message) => ({
        ...message,
        usernameColor: getUsernameColor(message.username),
      })),
    [messages],
  );

  function sendMessage(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!canSendMessages) {
      return;
    }

    const text = draftMessage.trim();

    if (!text) {
      return;
    }

    setMessages((currentMessages) => [
      ...currentMessages,
      {
        id: `local-${Date.now()}`,
        sentAt: getCurrentTime(),
        username: playerName,
        text,
      },
    ]);
    setDraftMessage("");
  }

  return (
    <section className="chat-font hidden w-[28rem] flex-col bg-black/55 shadow-[0_0_0_3px_#050302,0_4px_0_3px_rgba(0,0,0,0.55),inset_0_3px_0_rgba(255,255,255,0.08)] backdrop-blur-[2px] lg:flex" style={{ height: "28rem" }}>
      <div className="flex-1 overflow-y-auto px-4 py-3 text-xs leading-6 [scrollbar-color:#b8893b_rgba(0,0,0,0.35)]">
        {coloredMessages.map((message) => (
          <p key={message.id} className="text-[#f5dfad]/90">
            <span className="text-[#d9b46b]/80">{message.sentAt}</span>{" "}
            <span style={{ color: message.usernameColor }}>
              {message.username}:
            </span>{" "}
            <span>{message.text}</span>
          </p>
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
          maxLength={140}
          onChange={(event) => setDraftMessage(event.target.value)}
          placeholder={
            canSendMessages ? translations.placeholder : translations.signInToSend
          }
          value={draftMessage}
        />
      </form>
    </section>
  );
}
