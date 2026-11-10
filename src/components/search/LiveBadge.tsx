"use client";

import { useNow } from "@/hooks/useNow";

function fmt(ms: number): string {
  const total = Math.max(0, Math.round(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h > 0) return `${h}h ${String(m).padStart(2, "0")}m`;
  return `${m}:${String(s).padStart(2, "0")}`;
}

/** LIVE badge + countdown: "Ready in 12:30", then "Ends in 3h 05m". */
export function LiveBadge({ readyAt, availableUntil }: { readyAt: string | null; availableUntil: string | null }) {
  const now = useNow(1000);
  const ready = readyAt ? Date.parse(readyAt) : null;
  const until = availableUntil ? Date.parse(availableUntil) : null;
  let text: string | null = null;
  if (ready != null && ready > now) text = `Ready in ${fmt(ready - now)}`;
  else if (until != null && until > now) text = `Ends in ${fmt(until - now)}`;
  else if (until != null) text = "Ended";
  return (
    <span className="inline-flex items-center gap-1.5">
      <span className="inline-flex items-center gap-1 rounded-full bg-red-600 px-2 py-0.5 text-xs font-bold tracking-wide text-white">
        <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-white" aria-hidden />
        LIVE
      </span>
      {text && (
        <span className="text-xs font-medium tabular-nums text-red-700" aria-live="off">
          {text}
        </span>
      )}
    </span>
  );
}
