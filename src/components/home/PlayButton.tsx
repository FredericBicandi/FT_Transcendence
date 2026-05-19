type PlayButtonProps = {
  label: string;
  onClick: () => void;
};

export function PlayButton({ label, onClick }: PlayButtonProps) {
  return (
    <button
      onClick={onClick}
      className="relative overflow-hidden bg-[#6c4724] px-16 py-6 text-xl font-bold uppercase text-[#f5dfad] shadow-[0_0_0_4px_#050302,0_8px_0_4px_#2b160d,inset_0_6px_0_#8a6034,inset_0_-6px_0_#3d2414] before:absolute before:left-5 before:top-4 before:h-1 before:w-12 before:bg-[#3d2414] before:shadow-[42px_12px_0_#8a6034,96px_-2px_0_#3d2414,134px_18px_0_#8a6034] after:absolute after:bottom-5 after:left-10 after:h-1 after:w-8 after:bg-[#2b160d] after:shadow-[54px_-10px_0_#8a6034,112px_0_0_#2b160d,158px_-14px_0_#8a6034] hover:bg-[#75502b] hover:shadow-[0_0_0_4px_#050302,0_8px_0_4px_#2b160d,inset_0_6px_0_#9a6c3d,inset_0_-6px_0_#3d2414] active:translate-y-1 active:shadow-[0_0_0_4px_#050302,0_4px_0_4px_#2b160d,inset_0_4px_0_#8a6034,inset_0_-4px_0_#3d2414]"
      type="button"
    >
      <span className="relative z-10">{label}</span>
    </button>
  );
}
