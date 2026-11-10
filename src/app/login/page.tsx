"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState } from "react";
import { getSupabase } from "@/lib/supabase/client";
import { useUser } from "@/hooks/useUser";

/** Only allow same-site relative redirects (no open redirect via ?next=). */
function safeNext(next: string | null): string {
  return next && next.startsWith("/") && !next.startsWith("//") ? next : "/search";
}

function LoginForm() {
  const router = useRouter();
  const params = useSearchParams();
  const next = safeNext(params.get("next"));
  const { user } = useUser();
  const [email, setEmail] = useState("");
  const [state, setState] = useState<"idle" | "sending" | "sent" | "error">("idle");

  useEffect(() => {
    if (user) router.replace(next);
  }, [user, next, router]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setState("sending");
    const { error } = await getSupabase().auth.signInWithOtp({
      email,
      options: { emailRedirectTo: `${window.location.origin}/login?next=${encodeURIComponent(next)}` },
    });
    setState(error ? "error" : "sent");
  }

  return (
    <main className="mx-auto max-w-md px-4 py-16">
      <h1 className="text-2xl font-bold">Sign in</h1>
      <p className="mt-1 text-stone-600">We&apos;ll email you a magic link — needed to save searches and get alerts.</p>
      {state === "sent" ? (
        <p className="mt-6 rounded-xl bg-emerald-50 p-4 text-emerald-800" role="status">Check your inbox for the sign-in link.</p>
      ) : (
        <form onSubmit={submit} className="mt-6 space-y-3">
          <label className="block">
            <span className="text-sm font-medium">Email</span>
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="mt-1 w-full rounded-xl border border-stone-300 px-3 py-2"
              autoComplete="email"
            />
          </label>
          <button disabled={state === "sending"} className="w-full rounded-xl bg-orange-500 py-2.5 font-semibold text-white hover:bg-orange-600 disabled:opacity-60">
            {state === "sending" ? "Sending…" : "Send magic link"}
          </button>
          {state === "error" && <p className="text-sm text-red-600" role="alert">Couldn&apos;t send the link. Try again.</p>}
        </form>
      )}
    </main>
  );
}

export default function LoginPage() {
  return (
    <Suspense>
      <LoginForm />
    </Suspense>
  );
}
