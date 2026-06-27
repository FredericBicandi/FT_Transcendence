import { useEffect, useRef } from "react";
import type { HomeTranslations } from "@/views/home/homeTranslations";

export type LegalDocument = "privacy" | "terms";

type LegalModalProps = {
  document: LegalDocument;
  isClosing?: boolean;
  onClose: () => void;
  translations: HomeTranslations["legal"];
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

export function LegalModal({
  document,
  isClosing = false,
  onClose,
  translations,
}: LegalModalProps) {
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const isPrivacyPolicy = document === "privacy";
  const title = isPrivacyPolicy
    ? translations.privacyPolicy
    : translations.termsOfService;
  const sections = isPrivacyPolicy
    ? translations.privacySections
    : translations.termsSections;
  const titleId = `legal-${document}-title`;

  useEffect(() => {
    closeButtonRef.current?.focus();
  }, []);

  return (
    <div
      className={`absolute inset-0 z-50 flex items-center justify-center bg-black/60 p-3 backdrop-blur-[2px] sm:p-6 ${
        isClosing ? "modal-backdrop-exit" : "modal-backdrop-enter"
      }`}
      onClick={onClose}
    >
      <section
        aria-labelledby={titleId}
        aria-modal="true"
        className={`relative flex h-[min(44rem,calc(100vh-2rem))] w-[min(54rem,calc(100vw-2rem))] min-h-0 flex-col overflow-hidden bg-[#151819]/90 px-5 pb-6 pt-14 shadow-[0_0_0_4px_#050302,0_8px_0_4px_#111515,inset_0_4px_0_#374041,inset_0_-4px_0_#050302] sm:px-8 sm:pb-8 sm:pt-16 ${
          isClosing ? "modal-panel-exit" : "modal-panel-enter"
        }`}
        onClick={(event) => event.stopPropagation()}
        role="dialog"
      >
        <button
          aria-label={translations.close}
          className="absolute left-3 top-3 flex h-9 w-9 items-center justify-center bg-black/80 text-[#f5dfad] shadow-[0_0_0_2px_#050302,inset_0_2px_0_#374041,inset_0_-2px_0_#050302] hover:bg-[#2a3031] hover:text-[#ead7a6] active:translate-y-0.5"
          onClick={onClose}
          ref={closeButtonRef}
          type="button"
        >
          <CloseIcon />
        </button>

        <header className="mb-5 shrink-0 border-b-2 border-[#b8893b]/70 pb-4 text-center sm:mb-6">
          <h2
            className="text-2xl uppercase text-[#f5dfad] sm:text-3xl"
            id={titleId}
          >
            {title}
          </h2>
          <p className="chat-font mt-2 text-[10px] text-[#d9b46b] sm:text-xs">
            {translations.lastUpdated}
          </p>
        </header>

        <div
          className="legal-scrollbar chat-font min-h-0 flex-1 space-y-6 overflow-y-auto bg-black/30 px-4 py-5 text-[#f5dfad] shadow-[inset_0_3px_0_#050302,inset_0_-3px_0_#374041] sm:px-6"
          tabIndex={0}
        >
          {sections.map((section) => (
            <section key={section.title}>
              <h3 className="mb-2 text-xs font-bold uppercase leading-5 text-[#e2b84f] sm:text-sm">
                {section.title}
              </h3>
              <p className="text-[11px] leading-6 text-[#f5dfad]/95 sm:text-xs sm:leading-7">
                {section.body}
              </p>
            </section>
          ))}
        </div>
      </section>
    </div>
  );
}
