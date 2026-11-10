import { NextResponse, type NextRequest } from "next/server";
import { sendNotification, setVapidDetails } from "web-push";
import { getSupabaseAdmin } from "@/lib/supabase/admin";
import { defaultSearchState, searchUrl } from "@/lib/search/params";

/**
 * Drains the saved-search alert queue (filled by database triggers when a matching
 * Kitchen Card / Cooking Now post goes live in range) and delivers push + email.
 *
 * Call every minute or few from a scheduler (vercel.json cron, GitHub Actions, or
 * pg_cron + pg_net) with:  Authorization: Bearer $CRON_SECRET
 */

export const dynamic = "force-dynamic";

interface ClaimedAlert {
  alert_id: number;
  user_id: string;
  email: string | null;
  notify_push: boolean;
  notify_email: boolean;
  query: string;
  item_type: "kitchen_card" | "cooking_now";
  item_id: string;
  title: string;
  cook_name: string;
  distance_m: number;
  unit: "mi" | "km";
  push_subscriptions: { endpoint: string; keys: { p256dh: string; auth: string } }[];
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}

function message(a: ClaimedAlert) {
  const dist = (a.distance_m / (a.unit === "km" ? 1000 : 1609.344)).toFixed(1);
  const verb = a.item_type === "cooking_now" ? "is cooking" : "now offers";
  const title = a.item_type === "cooking_now" ? `🔴 Live near you: ${a.title}` : `New near you: ${a.title}`;
  const body = `${a.cook_name} ${verb} “${a.title}” — ${dist} ${a.unit} away. (Your alert: ${a.query})`;
  const base = process.env.NEXT_PUBLIC_SITE_URL ?? "";
  // Link to the search rather than to coordinates: the alert must not leak the cook's location.
  const url = `${base}${searchUrl({ ...defaultSearchState(a.unit), q: a.query })}`;
  return { title, body, url };
}

async function sendEmail(to: string, subject: string, text: string, url: string): Promise<void> {
  const key = process.env.RESEND_API_KEY;
  if (!key) return;
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: process.env.ALERTS_FROM_EMAIL ?? "ShareYourPot <alerts@example.com>",
      to,
      subject,
      text: `${text}\n\n${url}`,
      html: `<p>${escapeHtml(text)}</p><p><a href="${escapeHtml(url)}">See it on ShareYourPot</a></p>`,
    }),
  });
  if (!res.ok) throw new Error(`email ${res.status}`);
}

async function handle(req: NextRequest) {
  const secret = process.env.CRON_SECRET;
  if (!secret || req.headers.get("authorization") !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const pushEnabled = !!(process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY && process.env.VAPID_PRIVATE_KEY);
  if (pushEnabled) {
    setVapidDetails(
      process.env.VAPID_SUBJECT ?? "mailto:alerts@example.com",
      process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY!,
      process.env.VAPID_PRIVATE_KEY!,
    );
  }

  const db = getSupabaseAdmin();
  const { data, error } = await db.rpc("claim_saved_search_alerts", { batch_size: 100 });
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  const alerts = (data ?? []) as ClaimedAlert[];

  let sent = 0;
  let failed = 0;
  for (const a of alerts) {
    const msg = message(a);
    const errors: string[] = [];
    let delivered = false;

    if (a.notify_push && pushEnabled) {
      for (const sub of a.push_subscriptions) {
        try {
          await sendNotification(sub, JSON.stringify({ ...msg, tag: `alert-${a.alert_id}` }), { TTL: 3600 });
          delivered = true;
        } catch (e) {
          const status = (e as { statusCode?: number }).statusCode;
          if (status === 404 || status === 410) {
            await db.rpc("delete_push_subscription", { p_endpoint: sub.endpoint }); // expired endpoint
          } else {
            errors.push(`push ${status ?? "error"}`);
          }
        }
      }
    }
    if (a.notify_email && a.email && process.env.RESEND_API_KEY) {
      try {
        await sendEmail(a.email, msg.title, msg.body, msg.url);
        delivered = true;
      } catch (e) {
        errors.push(e instanceof Error ? e.message : "email error");
      }
    }

    // Retry (up to 5 attempts, enforced in SQL) only if nothing got through.
    const err = delivered || errors.length === 0 ? null : errors.join("; ");
    await db.rpc("complete_saved_search_alert", { alert_id: a.alert_id, error: err });
    if (err) failed++;
    else sent++;
  }

  return NextResponse.json({ claimed: alerts.length, sent, failed });
}

export const GET = handle;
export const POST = handle;
