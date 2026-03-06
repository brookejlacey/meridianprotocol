"use client";

import type { ChatMessage as ChatMessageType } from "@/hooks/useChat";

export function ChatMessage({ message }: { message: ChatMessageType }) {
  const isUser = message.role === "user";

  return (
    <div className={`flex ${isUser ? "justify-end" : "justify-start"}`}>
      <div
        className={`max-w-[85%] px-3 py-2 rounded-lg text-sm leading-relaxed whitespace-pre-wrap break-words ${
          isUser
            ? "bg-[var(--accent)] text-black rounded-br-sm"
            : "bg-zinc-800 text-zinc-200 rounded-bl-sm"
        }`}
      >
        {formatContent(message.content)}
      </div>
    </div>
  );
}

function formatContent(text: string) {
  // Simple inline formatting: **bold** and `code`
  const parts = text.split(/(\*\*[^*]+\*\*|`[^`]+`)/g);
  return parts.map((part, i) => {
    if (part.startsWith("**") && part.endsWith("**")) {
      return (
        <strong key={i} className="font-semibold">
          {part.slice(2, -2)}
        </strong>
      );
    }
    if (part.startsWith("`") && part.endsWith("`")) {
      return (
        <code key={i} className="px-1 py-0.5 rounded bg-zinc-700 text-xs font-mono">
          {part.slice(1, -1)}
        </code>
      );
    }
    return part;
  });
}
