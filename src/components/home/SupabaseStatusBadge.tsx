import type { SupabaseStatus } from "@/controllers/home/useHomeController";

type SupabaseStatusBadgeProps = {
  label: string;
  status: SupabaseStatus;
};

export function SupabaseStatusBadge({
  label,
  status,
}: SupabaseStatusBadgeProps) {
  return (
    <p
      className={
        status === "connected" ? "text-sm text-green-400" : "text-sm text-yellow-400"
      }
    >
      {label}
    </p>
  );
}
