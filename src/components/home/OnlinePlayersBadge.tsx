type OnlinePlayersBadgeProps = {
  label: string;
  onlineCount: number;
};

export function OnlinePlayersBadge({
  label,
  onlineCount,
}: OnlinePlayersBadgeProps) {
  return (
    <div className="flex items-center gap-3 rounded border border-emerald-400/30 bg-black/45 px-4 py-2 shadow-[0_0_18px_rgba(16,185,129,0.18)]">
      <span className="relative flex h-4 w-4 items-center justify-center">
        <span className="absolute h-4 w-4 rounded-full bg-emerald-400 opacity-45 blur-[3px]" />
        <span className="h-2.5 w-2.5 rounded-full bg-emerald-300 shadow-[0_0_10px_#34d399]" />
      </span>
      <span className="text-sm text-emerald-100">
        {onlineCount} {label}
      </span>
    </div>
  );
}
