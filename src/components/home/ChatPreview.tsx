import { useMemo } from "react";
import {
  getUsernameColor,
  type ChatMessage,
} from "@/components/home/chatMessages";

type ChatPreviewProps = {
  messages: ChatMessage[];
};

const TONES = [
  {
    opacity: 1,
    textSize: "text-[12px]",
    bodyColor: "text-[#f5dfad]",
    weight: "font-normal",
  },
  {
    opacity: 0.5,
    textSize: "text-[11px]",
    bodyColor: "text-[#f5dfad]",
    weight: "font-normal",
  },
  {
    opacity: 0.2,
    textSize: "text-[10px]",
    bodyColor: "text-[#f5dfad]",
    weight: "font-normal",
  },
];

export function ChatPreview({ messages }: ChatPreviewProps) {
  const lastThree = useMemo(
    () =>
      messages
        .slice(-3)
        .reverse()
        .map((message) => ({
          ...message,
          usernameColor: getUsernameColor(message.username),
        })),
    [messages],
  );

  if (lastThree.length === 0) {
    return null;
  }

  return (
    <div
      aria-hidden="true"
      className="chat-font flex w-[min(30rem,calc(100vw-2rem))] flex-col items-center gap-[3px] text-center"
      style={{ textShadow: "0 1px 0 rgba(0,0,0,0.85)" }}
    >
      {lastThree.map((message, index) => {
        const tone = TONES[index] ?? TONES[TONES.length - 1];

        return (
          <p
            key={message.id}
            className={`max-w-full truncate ${tone.textSize} ${tone.bodyColor} ${tone.weight}`}
            style={{ opacity: tone.opacity }}
          >
            <span style={{ color: message.usernameColor }}>
              {message.username}
            </span>
            <span className="text-[#d9b46b]/70">: </span>
            <span>{message.text}</span>
          </p>
        );
      })}
    </div>
  );
}
