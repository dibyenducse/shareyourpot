import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = {
  title: "ShareYourPot — home-cooked food near you",
  description: "Find a dish near you: biryani, tacos, dumplings and more, cooked by neighbours.",
  icons: { icon: "/icon.svg" },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen">
        <header className="border-b border-stone-200 bg-white">
          <div className="mx-auto flex max-w-7xl items-center justify-between px-4 py-3">
            <Link href="/" className="text-lg font-bold tracking-tight">
              <span aria-hidden>🍲</span> ShareYourPot
            </Link>
            <nav className="flex items-center gap-4 text-sm text-stone-600">
              <Link href="/search" className="hover:text-stone-900">Find a dish</Link>
              <Link href="/saved" className="hover:text-stone-900">My alerts</Link>
            </nav>
          </div>
        </header>
        {children}
      </body>
    </html>
  );
}
