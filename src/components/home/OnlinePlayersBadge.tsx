type OnlinePlayersBadgeProps = {
  label: string;
  onlineCount: number;
};

export function OnlinePlayersBadge({
  label,
  onlineCount,
}: OnlinePlayersBadgeProps) {
  return (
    <div className="flex h-10 w-[12rem] items-center justify-center gap-3 rounded border border-emerald-900/40 bg-black/45 px-4 py-2">
      {/* Draw the status dot as pixels so it matches the game art. */}
      <span className="grid h-[10px] w-[10px] grid-cols-5 grid-rows-5 [image-rendering:pixelated]">
        <span className="col-start-2 row-start-1 bg-[#1a6b1a]" />
        <span className="col-start-3 row-start-1 bg-[#1a6b1a]" />
        <span className="col-start-4 row-start-1 bg-[#1a6b1a]" />
        <span className="col-start-1 row-start-2 bg-[#1a6b1a]" />
        <span className="col-start-2 row-start-2 bg-[#1a6b1a]" />
        <span className="col-start-3 row-start-2 bg-[#1a6b1a]" />
        <span className="col-start-4 row-start-2 bg-[#1a6b1a]" />
        <span className="col-start-5 row-start-2 bg-[#1a6b1a]" />
        <span className="col-start-1 row-start-3 bg-[#1a6b1a]" />
        <span className="col-start-2 row-start-3 bg-[#1a6b1a]" />
        <span className="col-start-3 row-start-3 bg-[#1a6b1a]" />
        <span className="col-start-4 row-start-3 bg-[#1a6b1a]" />
        <span className="col-start-5 row-start-3 bg-[#1a6b1a]" />
        <span className="col-start-1 row-start-4 bg-[#1a6b1a]" />
        <span className="col-start-2 row-start-4 bg-[#1a6b1a]" />
        <span className="col-start-3 row-start-4 bg-[#1a6b1a]" />
        <span className="col-start-4 row-start-4 bg-[#1a6b1a]" />
        <span className="col-start-5 row-start-4 bg-[#1a6b1a]" />
        <span className="col-start-2 row-start-5 bg-[#1a6b1a]" />
        <span className="col-start-3 row-start-5 bg-[#1a6b1a]" />
        <span className="col-start-4 row-start-5 bg-[#1a6b1a]" />
      </span>
      <span className="min-w-[6.5rem] text-center text-sm text-emerald-100 tabular-nums">
        {onlineCount} {label}
      </span>
    </div>
  );
}
