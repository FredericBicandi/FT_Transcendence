type LoginSignupButtonProps = {
  label: string;
  onClick?: () => void;
};

export function LoginSignupButton({ label, onClick }: LoginSignupButtonProps) {
  return (
    <button
      onClick={onClick}
      className="bg-[#344326] px-6 py-2 text-sm uppercase text-[#d9b46b] shadow-[0_0_0_3px_#050302,0_4px_0_3px_#172111,inset_0_3px_0_#53663a,inset_0_-3px_0_#202b17] hover:bg-[#40522d] hover:text-[#ead08a] active:translate-y-1 active:shadow-[0_0_0_3px_#050302,0_1px_0_3px_#172111,inset_0_2px_0_#53663a,inset_0_-2px_0_#202b17]"
      type="button"
    >
      {label}
    </button>
  );
}
