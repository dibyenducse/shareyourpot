"use client";

import { getSupabase } from "@/lib/supabase/client";

function urlBase64ToUint8Array(base64: string): Uint8Array<ArrayBuffer> {
  const padding = "=".repeat((4 - (base64.length % 4)) % 4);
  const raw = atob((base64 + padding).replace(/-/g, "+").replace(/_/g, "/"));
  const out = new Uint8Array(new ArrayBuffer(raw.length));
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

export function pushSupported(): boolean {
  return (
    typeof window !== "undefined" &&
    "serviceWorker" in navigator &&
    "PushManager" in window &&
    !!process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY
  );
}

/**
 * Ask for notification permission and store this browser's push subscription.
 * Returns false when unsupported / denied (email alerts still work).
 */
export async function enablePushAlerts(): Promise<boolean> {
  if (!pushSupported()) return false;
  if ((await Notification.requestPermission()) !== "granted") return false;
  const reg = await navigator.serviceWorker.register("/sw.js");
  await navigator.serviceWorker.ready;
  const sub =
    (await reg.pushManager.getSubscription()) ??
    (await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY!),
    }));
  const json = sub.toJSON();
  const { error } = await getSupabase()
    .from("push_subscriptions")
    .upsert({ endpoint: json.endpoint, p256dh: json.keys?.p256dh, auth: json.keys?.auth }, { onConflict: "endpoint" });
  return !error;
}
