"use client";

import { useEffect, useState } from "react";
import { pingSupabase } from "@/models/supabase/client.model";

export type SupabaseStatus = "checking" | "connected" | "missing-env" | "error";

const supabaseStatusLabels: Record<SupabaseStatus, string> = {
  checking: "Checking Supabase...",
  connected: "Supabase connected",
  "missing-env": "Supabase env missing",
  error: "Supabase connection failed",
};

export function useHomeController() {
  const [showGame, setShowGame] = useState(false);
  const [supabaseStatus, setSupabaseStatus] =
    useState<SupabaseStatus>("checking");

  useEffect(() => {
    let mounted = true;

    async function checkSupabase() {
      try {
        await pingSupabase();

        if (mounted) {
          setSupabaseStatus("connected");
        }
      } catch (error) {
        if (!mounted) {
          return;
        }

        setSupabaseStatus(
          error instanceof Error &&
            error.message.includes("Missing Supabase environment variables")
            ? "missing-env"
            : "error",
        );
      }
    }

    checkSupabase();

    return () => {
      mounted = false;
    };
  }, []);

  return {
    onlineCount: 0,
    showGame,
    supabaseStatus,
    supabaseStatusLabel: supabaseStatusLabels[supabaseStatus],
    playGame: () => setShowGame(true),
  };
}
