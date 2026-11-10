import type { Metadata } from "next";
import { Suspense } from "react";
import { SearchPage } from "@/components/search/SearchPage";

export const metadata: Metadata = { title: "Find a dish near me — ShareYourPot" };

export default function Page() {
  return (
    <Suspense fallback={<div className="mx-auto max-w-7xl p-4 text-stone-500">Loading search…</div>}>
      <SearchPage />
    </Suspense>
  );
}
