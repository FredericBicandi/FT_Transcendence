type OnlinePlayersBadgeProps = {
  label: string;
  onlineCount: number;
};

export function OnlinePlayersBadge({
  label,
  onlineCount,
}: OnlinePlayersBadgeProps) {
  return (
    <div className="flex items-center gap-3 rounded border border-emerald-900/40 bg-black/45 px-4 py-2">
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
      <span className="text-sm text-emerald-100">
        {onlineCount} {label}
      </span>
    </div>
  );
}
