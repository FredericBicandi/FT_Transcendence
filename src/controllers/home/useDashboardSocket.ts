"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { PlayerProfile } from "@/models/player/playerProfile.model";

const MAX_CHAT_MESSAGES = 100;
const MAX_RECONNECT_DELAY_MS = 15_000;
const INITIAL_RECONNECT_DELAY_MS = 1_000;

export type DashboardChatMessage = {
  messageId: string;
  playerId: string;
  playerName: string;
  content: string;
  sentAt: string;
};

export type DashboardSocketError = {
  code: string;
  message: string;
};

type DashboardServerMessage =
  | {
      type: "global_chat";
      messageId: string;
      playerId: string;
      playerName: string;
      content: string;
      sentAt: string;
    }
  | {
      type: "online_count";
      count: number;
    }
  | {
      type: "ping";
    }
  | {
      type: "error";
      code: string;
      message: string;
    };

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function parseServerMessage(value: string): DashboardServerMessage | null {
  let parsedValue: unknown;

  try {
    parsedValue = JSON.parse(value);
  } catch {
    return null;
  }

  if (!isRecord(parsedValue) || typeof parsedValue.type !== "string") {
    return null;
  }

  if (
    parsedValue.type === "online_count" &&
    typeof parsedValue.count === "number" &&
    Number.isFinite(parsedValue.count) &&
    parsedValue.count >= 0
  ) {
    return {
      type: "online_count",
      count: Math.floor(parsedValue.count),
    };
  }

  if (parsedValue.type === "ping") {
    return { type: "ping" };
  }

  if (
    parsedValue.type === "error" &&
    typeof parsedValue.code === "string" &&
    typeof parsedValue.message === "string"
  ) {
    return {
      type: "error",
      code: parsedValue.code,
      message: parsedValue.message,
    };
  }

  if (
    parsedValue.type === "global_chat" &&
    typeof parsedValue.messageId === "string" &&
    typeof parsedValue.playerId === "string" &&
    typeof parsedValue.playerName === "string" &&
    typeof parsedValue.content === "string" &&
    typeof parsedValue.sentAt === "string"
  ) {
    return {
      type: "global_chat",
      messageId: parsedValue.messageId,
      playerId: parsedValue.playerId,
      playerName: parsedValue.playerName,
      content: parsedValue.content,
      sentAt: parsedValue.sentAt,
    };
  }

  return null;
}

function createDashboardSocketUrl() {
  const configuredUrl = process.env.NEXT_PUBLIC_DASHBOARD_WS_URL?.trim();

  try {
    const socketUrl = configuredUrl
      ? new URL(configuredUrl)
      : new URL(
          "/ws/dashboard",
          `${
            window.location.protocol === "https:" ? "wss:" : "ws:"
          }//${window.location.host}`,
        );

    if (socketUrl.protocol !== "ws:" && socketUrl.protocol !== "wss:") {
      return null;
    }

    return socketUrl.toString();
  } catch {
    return null;
  }
}

export function useDashboardSocket() {
  const socketRef = useRef<WebSocket | null>(null);
  const [chatMessages, setChatMessages] = useState<DashboardChatMessage[]>([]);
  const [error, setError] = useState<DashboardSocketError | null>(null);
  const [isConnected, setIsConnected] = useState(false);
  const [onlineCount, setOnlineCount] = useState(0);

  useEffect(() => {
    let disposed = false;
    let reconnectAttempt = 0;
    let reconnectTimer: number | null = null;

    function clearReconnectTimer() {
      if (reconnectTimer !== null) {
        window.clearTimeout(reconnectTimer);
        reconnectTimer = null;
      }
    }

    function connect() {
      if (disposed) {
        return;
      }

      clearReconnectTimer();

      const socketUrl = createDashboardSocketUrl();

      if (!socketUrl) {
        return;
      }

      setIsConnected(false);
      socketRef.current?.close();

      const socket = new WebSocket(socketUrl);
      socketRef.current = socket;

      socket.addEventListener("open", () => {
        if (socketRef.current !== socket) {
          return;
        }

        reconnectAttempt = 0;
        setError(null);
        setIsConnected(true);
      });

      socket.addEventListener("message", (event: MessageEvent<unknown>) => {
        if (socketRef.current !== socket || typeof event.data !== "string") {
          return;
        }

        const message = parseServerMessage(event.data);

        if (!message) {
          return;
        }

        if (message.type === "online_count") {
          setOnlineCount(message.count);
          return;
        }

        if (message.type === "ping") {
          if (socket.readyState === WebSocket.OPEN) {
            socket.send(JSON.stringify({ type: "pong" }));
          }
          return;
        }

        if (message.type === "error") {
          setError({
            code: message.code,
            message: message.message,
          });
          return;
        }

        setChatMessages((currentMessages) => {
          if (
            currentMessages.some(
              (currentMessage) =>
                currentMessage.messageId === message.messageId,
            )
          ) {
            return currentMessages;
          }

          return [...currentMessages, message].slice(-MAX_CHAT_MESSAGES);
        });
      });

      socket.addEventListener("close", () => {
        if (socketRef.current !== socket || disposed) {
          return;
        }

        socketRef.current = null;
        setIsConnected(false);

        const reconnectDelay = Math.min(
          INITIAL_RECONNECT_DELAY_MS * 2 ** reconnectAttempt,
          MAX_RECONNECT_DELAY_MS,
        );
        reconnectAttempt += 1;
        reconnectTimer = window.setTimeout(connect, reconnectDelay);
      });

      socket.addEventListener("error", () => {
        socket.close();
      });
    }

    connect();

    return () => {
      disposed = true;
      clearReconnectTimer();
      socketRef.current?.close();
      socketRef.current = null;
    };
  }, []);

  const sendChatMessage = useCallback((
    content: string,
    playerProfile: PlayerProfile,
  ) => {
    const socket = socketRef.current;
    const normalizedContent = content.trim();

    if (
      !socket ||
      socket.readyState !== WebSocket.OPEN ||
      !normalizedContent ||
      Array.from(normalizedContent).length > 140
    ) {
      return false;
    }

    setError(null);
    socket.send(
      JSON.stringify({
        type: "global_chat",
        playerId: playerProfile.playerId,
        playerName: playerProfile.playerName,
        content: normalizedContent,
      }),
    );

    return true;
  }, []);

  return {
    chatMessages,
    error,
    isConnected,
    onlineCount,
    sendChatMessage,
  };
}
