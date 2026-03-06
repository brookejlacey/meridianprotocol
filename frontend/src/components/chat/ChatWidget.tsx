"use client";

import { useState } from "react";
import { ChatPanel } from "./ChatPanel";

export function ChatWidget() {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <>
      {isOpen && <ChatPanel onClose={() => setIsOpen(false)} />}

      {/* Floating chat button */}
      {!isOpen && (
        <button
          onClick={() => setIsOpen(true)}
          className="fixed bottom-4 right-4 z-50 flex items-center gap-3 px-5 py-3 rounded-2xl bg-[var(--accent)] hover:bg-[var(--accent-hover)] shadow-lg shadow-[var(--accent)]/20 hover:shadow-[var(--accent)]/25 transition-all duration-200 hover:scale-[1.02] group"
        >
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" className="w-5 h-5 text-white shrink-0">
            <path fillRule="evenodd" d="M3.43 2.524A41.29 41.29 0 0 1 10 2c2.236 0 4.43.18 6.57.524 1.437.231 2.43 1.49 2.43 2.902v5.148c0 1.413-.993 2.67-2.43 2.902a41.202 41.202 0 0 1-5.183.501.78.78 0 0 0-.528.224l-3.579 3.58A.75.75 0 0 1 6 17.25v-3.443a.75.75 0 0 0-.663-.744 41.662 41.662 0 0 1-1.907-.33C1.993 12.47 1 11.214 1 9.8V5.426c0-1.413.993-2.67 2.43-2.902Z" clipRule="evenodd" />
          </svg>
          <div className="text-left">
            <div className="text-sm font-semibold text-white leading-tight">Meridian Assistant</div>
            <div className="text-xs text-blue-200 leading-tight">Ask anything about the protocol</div>
          </div>
        </button>
      )}
    </>
  );
}
