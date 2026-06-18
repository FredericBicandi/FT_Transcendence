// AuthModal owns OAuth and email OTP sign-in UI.
// It communicates with Supabase auth, the auth callback URL helper, and HomeView modal state.
// Do not casually change OTP guards, callback URLs, or duplicate-submit protection.

import {
  useRef,
  useState,
  type ClipboardEvent,
  type FormEvent,
  type KeyboardEvent,
} from "react";
import type { HomeTranslations } from "@/views/home/homeTranslations";
import { getAuthCallbackUrl } from "@/models/app/appUrl.model";
import { createSupabaseClient } from "@/models/supabase/client.model";

const OTP_CODE_LENGTH = 6;
type OAuthProvider = "github" | "google";

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
  const [email, setEmail] = useState("");
  const [otpCode, setOtpCode] = useState("");
  const [hasSentOtp, setHasSentOtp] = useState(false);
  const [sentOtpEmail, setSentOtpEmail] = useState("");
  const [isEmailAuthLoading, setIsEmailAuthLoading] = useState(false);
  const [emailAuthMessage, setEmailAuthMessage] = useState<string | null>(
    null,
  );
  const isRequestingOtpRef = useRef(false);
  const isVerifyingOtpRef = useRef(false);
  const otpInputRefs = useRef<Array<HTMLInputElement | null>>([]);
  const normalizedEmail = email.trim().toLowerCase();
  const normalizedOtpCode = otpCode.replace(/\D/g, "").slice(
    0,
    OTP_CODE_LENGTH,
  );
  // Store OTP as one value so paste/backspace logic stays consistent across all boxes.
  const otpDigits = Array.from(
    { length: OTP_CODE_LENGTH },
    (_, index) => normalizedOtpCode[index] ?? "",
  );

  async function signInWithProvider(provider: OAuthProvider) {
    setEmailAuthMessage(null);

    try {
      const supabase = createSupabaseClient();
      const { error } = await supabase.auth.signInWithOAuth({
        provider,
        options: {
          redirectTo: getAuthCallbackUrl(),
        },
      });

      if (error) {
        setEmailAuthMessage(error.message || translations.authFailed);
      }
    } catch (error) {
      console.error("OAuth sign-in failed before Supabase returned a response.", error);
      setEmailAuthMessage(translations.authFailed);
    }
  }

  async function signInWithGoogle() {
    await signInWithProvider("google");
  }

  async function signInWithGithub() {
    await signInWithProvider("github");
  }

  async function requestEmailOtp() {
    if (isRequestingOtpRef.current || isEmailAuthLoading || hasSentOtp) {
      return;
    }

    if (!normalizedEmail) {
      setEmailAuthMessage(translations.emailRequired);
      return;
    }

    isRequestingOtpRef.current = true;
    setIsEmailAuthLoading(true);
    setEmailAuthMessage(null);
    setOtpCode("");

    try {
      const supabase = createSupabaseClient();
      const { error } = await supabase.auth.signInWithOtp({
        email: normalizedEmail,
      });

      if (error) {
        setEmailAuthMessage(error.message || translations.authFailed);
        return;
      }

      setSentOtpEmail(normalizedEmail);
      setHasSentOtp(true);
      setEmailAuthMessage(translations.codeSent);
    } catch (error) {
      console.error("Email OTP request failed before Supabase returned a response.", error);
      setEmailAuthMessage(translations.authFailed);
    } finally {
      isRequestingOtpRef.current = false;
      setIsEmailAuthLoading(false);
    }
  }

  async function verifyEmailOtp() {
    if (isVerifyingOtpRef.current || isEmailAuthLoading) {
      return;
    }

    const emailToVerify = sentOtpEmail || normalizedEmail;

    if (!emailToVerify) {
      setEmailAuthMessage(translations.emailRequired);
      return;
    }

    if (normalizedOtpCode.length < OTP_CODE_LENGTH) {
      setEmailAuthMessage(translations.codeRequired);
      return;
    }

    isVerifyingOtpRef.current = true;
    setIsEmailAuthLoading(true);
    setEmailAuthMessage(null);

    try {
      const supabase = createSupabaseClient();
      const { error } = await supabase.auth.verifyOtp({
        email: emailToVerify,
        token: normalizedOtpCode,
        type: "email",
      });

      if (error) {
        setEmailAuthMessage(error.message || translations.authFailed);
        return;
      }

      onClose();
    } catch (error) {
      console.error("Email OTP verification failed before Supabase returned a response.", error);
      setEmailAuthMessage(translations.authFailed);
    } finally {
      isVerifyingOtpRef.current = false;
      setIsEmailAuthLoading(false);
    }
  }

  async function handleEmailAuthSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (hasSentOtp) {
      await verifyEmailOtp();
      return;
    }

    await requestEmailOtp();
  }

  function focusOtpInput(index: number) {
    otpInputRefs.current[index]?.focus();
    otpInputRefs.current[index]?.select();
  }

  function replaceOtpDigits(startIndex: number, value: string) {
    const nextDigits = [...otpDigits];
    // Paste can fill the rest of the OTP from any digit-only text.
    const pastedDigits = value.replace(/\D/g, "").slice(
      0,
      OTP_CODE_LENGTH - startIndex,
    );

    if (!pastedDigits) {
      return;
    }

    pastedDigits.split("").forEach((digit, digitIndex) => {
      nextDigits[startIndex + digitIndex] = digit;
    });

    setOtpCode(nextDigits.join(""));
    setEmailAuthMessage(null);
    focusOtpInput(Math.min(startIndex + pastedDigits.length, OTP_CODE_LENGTH - 1));
  }

  function handleOtpChange(index: number, value: string) {
    if (!value.replace(/\D/g, "")) {
      const nextDigits = [...otpDigits];
      nextDigits[index] = "";
      setOtpCode(nextDigits.join(""));
      setEmailAuthMessage(null);
      return;
    }

    replaceOtpDigits(index, value);
  }

  function handleOtpKeyDown(
    index: number,
    event: KeyboardEvent<HTMLInputElement>,
  ) {
    if (event.key === "Backspace" && !otpDigits[index] && index > 0) {
      // Backspace should feel like one connected OTP input.
      event.preventDefault();
      const nextDigits = [...otpDigits];
      nextDigits[index - 1] = "";
      setOtpCode(nextDigits.join(""));
      setEmailAuthMessage(null);
      focusOtpInput(index - 1);
    }
  }

  function handleOtpPaste(
    index: number,
    event: ClipboardEvent<HTMLInputElement>,
  ) {
    event.preventDefault();
    replaceOtpDigits(index, event.clipboardData.getData("text"));
  }

  return (
    <div
      className="absolute inset-0 z-40 flex items-center justify-center bg-black/35 px-4 backdrop-blur-[2px]"
      onClick={onClose}
    >
      <div
        className="relative flex min-h-[32rem] w-[min(23rem,calc(100vw-2rem))] flex-col justify-center gap-8 bg-[#212627]/95 px-7 py-16 shadow-[0_0_0_4px_#050302,0_8px_0_4px_#111515,inset_0_4px_0_#374041,inset_0_-4px_0_#151819] sm:min-h-[36rem] sm:px-8"
        onClick={(event) => event.stopPropagation()}
      >
        <button
          aria-label={translations.close}
          className="absolute left-3 top-3 flex h-9 w-9 items-center justify-center bg-[#151819] text-[#f5dfad] shadow-[0_0_0_2px_#050302,inset_0_2px_0_#374041,inset_0_-2px_0_#050302] hover:bg-[#2a3031] hover:text-[#ead7a6] active:translate-y-0.5"
          onClick={onClose}
          type="button"
        >
          <CloseIcon />
        </button>

        <form className="flex flex-col gap-4" onSubmit={handleEmailAuthSubmit}>
          <label className="flex h-16 items-center gap-4 bg-[#151819] px-4 shadow-[inset_0_4px_0_#050302,inset_0_-4px_0_#374041] focus-within:shadow-[0_0_0_2px_#b8893b,inset_0_4px_0_#050302,inset_0_-4px_0_#374041]">
            <MailIcon />
            <input
              aria-label={translations.email}
              className="chat-font min-w-0 flex-1 bg-transparent text-[10px] text-[#f5dfad] outline-none placeholder:text-[#d9b46b]/70"
              disabled={isEmailAuthLoading || hasSentOtp}
              onChange={(event) => {
                setEmail(event.target.value);
                setEmailAuthMessage(null);
              }}
              placeholder={translations.email}
              type="email"
              value={email}
            />
          </label>

          {hasSentOtp && (
            <div
              aria-label={translations.code}
              className="grid grid-cols-6 gap-2"
              role="group"
            >
              {otpDigits.map((digit, index) => (
                <input
                  aria-label={`${translations.code} ${index + 1}`}
                  className="h-12 min-w-0 bg-[#151819] text-center text-lg text-[#f5dfad] shadow-[inset_0_3px_0_#050302,inset_0_-3px_0_#374041] outline-none focus:shadow-[0_0_0_2px_#b8893b,inset_0_3px_0_#050302,inset_0_-3px_0_#374041] disabled:cursor-not-allowed disabled:text-[#8a8170]"
                  disabled={isEmailAuthLoading}
                  inputMode="numeric"
                  key={index}
                  maxLength={1}
                  onChange={(event) =>
                    handleOtpChange(index, event.target.value)
                  }
                  onKeyDown={(event) => handleOtpKeyDown(index, event)}
                  onPaste={(event) => handleOtpPaste(index, event)}
                  ref={(input) => {
                    otpInputRefs.current[index] = input;
                  }}
                  type="text"
                  value={digit}
                />
              ))}
            </div>
          )}

          {emailAuthMessage && (
            <p className="text-center text-[10px] uppercase leading-5 text-[#f5dfad]">
              {emailAuthMessage}
            </p>
          )}

          <button
            className="h-16 bg-[#344326] px-3 text-base uppercase text-[#d9b46b] shadow-[0_0_0_3px_#050302,0_5px_0_3px_#172111,inset_0_4px_0_#53663a,inset_0_-4px_0_#202b17] hover:bg-[#40522d] hover:text-[#ead08a] active:translate-y-1 active:shadow-[0_0_0_3px_#050302,0_2px_0_3px_#172111,inset_0_3px_0_#53663a,inset_0_-3px_0_#202b17] disabled:cursor-not-allowed disabled:bg-[#303536] disabled:text-[#8a8170] disabled:shadow-[0_0_0_3px_#050302,0_5px_0_3px_#151819,inset_0_4px_0_#4a5051,inset_0_-4px_0_#202425]"
            disabled={isEmailAuthLoading}
            type="submit"
          >
            {isEmailAuthLoading
              ? hasSentOtp
                ? translations.verifyingCode
                : translations.sendingCode
              : hasSentOtp
                ? translations.verifyCode
                : translations.sendCode}
          </button>
        </form>

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
            onClick={signInWithGithub}
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
