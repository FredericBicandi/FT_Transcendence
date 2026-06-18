"use client";

// useDashboardSocket owns the live dashboard WebSocket for online count and global chat.
// It communicates with the dashboard WS endpoint, localStorage presence IDs, and useHomeController.
// Do not casually change message parsing, presence identity, reconnect timing, or chat length limits.

import { useCallback, useEffect, useRef, useState } from "react";
import type { PlayerProfile } from "@/models/player/playerProfile.model";

const MAX_CHAT_MESSAGES = 100;
const MAX_RECONNECT_DELAY_MS = 15_000;
const INITIAL_RECONNECT_DELAY_MS = 1_000;
const DASHBOARD_PRESENCE_STORAGE_KEY = "dashboardPresenceId";

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

  // Treat socket payloads as untrusted; only accepted shapes reach React state.
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
    typeof parsedValue.message_id === "string" &&
    typeof parsedValue.player_id === "string" &&
    typeof parsedValue.player_name === "string" &&
    typeof parsedValue.content === "string" &&
    typeof parsedValue.sent_at === "string"
  ) {
    return {
      type: "global_chat",
      messageId: parsedValue.message_id,
      playerId: parsedValue.player_id,
      playerName: parsedValue.player_name,
      content: parsedValue.content,
      sentAt: parsedValue.sent_at,
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

    // Send a stable browser session so one tab refresh is not counted twice.
    socketUrl.searchParams.set("session_id", getDashboardPresenceId());

    return socketUrl.toString();
  } catch {
    return null;
  }
}

function createDashboardPresenceId() {
  if (typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }

  return `presence-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function getDashboardPresenceId() {
  try {
    const savedPresenceId = window.localStorage.getItem(
      DASHBOARD_PRESENCE_STORAGE_KEY,
    );

    if (savedPresenceId) {
      return savedPresenceId;
    }

    // Keep this id in localStorage so reloads reuse the same online presence.
    const nextPresenceId = createDashboardPresenceId();
    window.localStorage.setItem(
      DASHBOARD_PRESENCE_STORAGE_KEY,
      nextPresenceId,
    );
    return nextPresenceId;
  } catch {
    return createDashboardPresenceId();
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
        // Do not keep showing the last count when the socket cannot start.
        setOnlineCount(0);
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
        // Also send presence in the first message for older server paths.
        socket.send(
          JSON.stringify({
            type: "presence",
            session_id: getDashboardPresenceId(),
          }),
        );
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
            // Keep the server heartbeat alive so stale tabs get cleaned up.
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
          // Ignore duplicates from reconnects or repeated broadcasts.
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
        // Reset stale online count while the socket reconnects.
        setOnlineCount(0);

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
        player_id: playerProfile.playerId,
        player_name: playerProfile.playerName,
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
