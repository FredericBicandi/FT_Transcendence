import type { HomeTranslations } from "@/views/home/homeTranslations";
import { createSupabaseClient } from "@/models/supabase/client.model";

const appUrl = process.env.NEXT_PUBLIC_APP_URL;

type AuthModalProps = {
  onClose: () => void;
  translations: HomeTranslations["auth"];
};

function CloseIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-5 w-5"
      fill="none"
      viewBox="0 0 24 24"
    >
      <path
        d="M6 6l12 12M18 6 6 18"
        stroke="currentColor"
        strokeLinecap="square"
        strokeWidth="3"
      />
    </svg>
  );
}

function GoogleIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-5 w-5"
      fill="none"
      viewBox="0 0 24 24"
    >
      <path
        d="M21 12.2c0-.72-.06-1.26-.18-1.8H12v3.42h5.18c-.1.86-.67 2.16-1.92 3.03v2.22h3.12C20.12 17.46 21 15.08 21 12.2Z"
        fill="#7dd3fc"
      />
      <path
        d="M12 21c2.5 0 4.6-.78 6.13-2.12l-2.92-2.22c-.78.52-1.83.9-3.21.9-2.46 0-4.54-1.54-5.29-3.68H3.5v2.29C5.02 19.02 8.22 21 12 21Z"
        fill="#86efac"
      />
      <path
        d="M6.7 13.88A5.44 5.44 0 0 1 6.4 12c0-.65.1-1.29.3-1.88V7.83H3.5A8.53 8.53 0 0 0 2.6 12c0 1.5.36 2.92.9 4.17l3.2-2.29Z"
        fill="#fde047"
      />
      <path
        d="M12 6.44c1.74 0 2.91.72 3.58 1.32l2.62-2.48C16.59 3.85 14.5 3 12 3 8.22 3 5.02 4.98 3.5 7.83l3.2 2.29C7.46 7.98 9.54 6.44 12 6.44Z"
        fill="#fca5a5"
      />
    </svg>
  );
}

function GithubIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-5 w-5"
      fill="currentColor"
      viewBox="0 0 24 24"
    >
      <path d="M12 2.8c-5.1 0-9.2 4.08-9.2 9.12 0 4.04 2.64 7.46 6.3 8.66.46.08.63-.2.63-.44v-1.56c-2.56.55-3.1-1.08-3.1-1.08-.42-1.04-1.02-1.32-1.02-1.32-.83-.56.06-.55.06-.55.92.06 1.4.94 1.4.94.82 1.39 2.14.99 2.66.76.08-.59.32-.99.58-1.22-2.04-.23-4.18-1.01-4.18-4.5 0-.99.36-1.8.95-2.44-.1-.23-.41-1.16.09-2.41 0 0 .77-.25 2.53.93A8.84 8.84 0 0 1 12 7.38c.78 0 1.55.1 2.29.31 1.75-1.18 2.52-.93 2.52-.93.5 1.25.19 2.18.09 2.41.59.64.95 1.45.95 2.44 0 3.5-2.15 4.27-4.19 4.5.33.28.62.83.62 1.67v2.36c0 .24.17.52.64.44a9.16 9.16 0 0 0 6.28-8.66c0-5.04-4.1-9.12-9.2-9.12Z" />
    </svg>
  );
}

function MailIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-5 w-5 text-[#d9b46b]"
      fill="none"
      viewBox="0 0 24 24"
    >
      <path
        d="M4 6h16v12H4V6Z"
        stroke="currentColor"
        strokeLinejoin="round"
        strokeWidth="2"
      />
      <path
        d="m5 7 7 6 7-6"
        stroke="currentColor"
        strokeLinecap="square"
        strokeLinejoin="round"
        strokeWidth="2"
      />
    </svg>
  );
}

export function AuthModal({ onClose, translations }: AuthModalProps) {
  async function signInWithGoogle() {
    const supabase = createSupabaseClient();

    await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: "https://pixelfight.live/auth/callback",
      },
    });
  }

  return (
    <div className="absolute inset-0 z-40 flex items-center justify-center bg-black/35 px-4 backdrop-blur-[2px]">
      <div className="relative flex min-h-[32rem] w-[min(23rem,calc(100vw-2rem))] flex-col justify-center gap-8 bg-[#212627]/95 px-7 py-16 shadow-[0_0_0_4px_#050302,0_8px_0_4px_#111515,inset_0_4px_0_#374041,inset_0_-4px_0_#151819] sm:min-h-[36rem] sm:px-8">
        <button
          aria-label={translations.close}
          className="absolute left-3 top-3 flex h-9 w-9 items-center justify-center bg-[#151819] text-[#f5dfad] shadow-[0_0_0_2px_#050302,inset_0_2px_0_#374041,inset_0_-2px_0_#050302] hover:bg-[#2a3031] hover:text-[#ead7a6] active:translate-y-0.5"
          onClick={onClose}
          type="button"
        >
          <CloseIcon />
        </button>

        <label className="flex h-16 items-center gap-4 bg-[#151819] px-4 shadow-[inset_0_4px_0_#050302,inset_0_-4px_0_#374041] focus-within:shadow-[0_0_0_2px_#b8893b,inset_0_4px_0_#050302,inset_0_-4px_0_#374041]">
          <MailIcon />
          <input
            aria-label={translations.email}
            className="chat-font min-w-0 flex-1 bg-transparent text-[10px] text-[#f5dfad] outline-none placeholder:text-[#d9b46b]/70"
            placeholder={translations.email}
            type="email"
          />
        </label>

        <button
          className="h-16 bg-[#344326] text-base uppercase text-[#d9b46b] shadow-[0_0_0_3px_#050302,0_5px_0_3px_#172111,inset_0_4px_0_#53663a,inset_0_-4px_0_#202b17] hover:bg-[#40522d] hover:text-[#ead08a] active:translate-y-1 active:shadow-[0_0_0_3px_#050302,0_2px_0_3px_#172111,inset_0_3px_0_#53663a,inset_0_-3px_0_#202b17]"
          type="button"
        >
          {translations.loginRegister}
        </button>

        <p className="text-center text-sm uppercase text-[#f5dfad]">
          {translations.connectVia}
        </p>

        <div className="grid grid-cols-2 gap-3">
          <button
            className="flex h-14 items-center justify-center gap-2 bg-[#151819] text-sm uppercase text-[#f5dfad] shadow-[0_0_0_2px_#050302,inset_0_3px_0_#374041,inset_0_-3px_0_#050302] hover:bg-[#2a3031] active:translate-y-0.5"
            onClick={signInWithGoogle}
            type="button"
          >
            <GoogleIcon />
            Google
          </button>
          <button
            className="flex h-14 items-center justify-center gap-2 bg-[#151819] text-sm uppercase text-[#f5dfad] shadow-[0_0_0_2px_#050302,inset_0_3px_0_#374041,inset_0_-3px_0_#050302] hover:bg-[#2a3031] active:translate-y-0.5"
            type="button"
          >
            <GithubIcon />
            Github
          </button>
        </div>
      </div>
    </div>
  );
}
