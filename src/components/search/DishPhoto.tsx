/* eslint-disable @next/next/no-img-element -- cook-uploaded photos come from arbitrary storage hosts */
const EMOJI: Record<string, string> = {
  rice: "🍚", tacos: "🌮", curry: "🍛", stew: "🍲", soup: "🍜", noodles: "🍜", dessert: "🍮",
  dumplings: "🥟", "street food": "🥙", appetizer: "🍢", breakfast: "🥞", fish: "🐟", pasta: "🍝",
  wrap: "🌯", pastry: "🥧", drink: "🥤", snack: "🥨", main: "🍽️",
};

function hue(seed: string): number {
  let h = 0;
  for (const ch of seed) h = (h * 31 + ch.charCodeAt(0)) % 360;
  return h;
}

export function DishPhoto({
  url, title, category, cuisine, className = "",
}: { url: string | null; title: string; category: string | null; cuisine: string | null; className?: string }) {
  if (url) {
    return <img src={url} alt={title} loading="lazy" className={`object-cover ${className}`} />;
  }
  const h = hue(cuisine ?? title);
  return (
    <div
      role="img"
      aria-label={title}
      className={`flex items-center justify-center text-5xl ${className}`}
      style={{ background: `linear-gradient(135deg, hsl(${h} 70% 88%), hsl(${(h + 40) % 360} 75% 76%))` }}
    >
      <span aria-hidden>{EMOJI[(category ?? "").toLowerCase()] ?? "🍲"}</span>
    </div>
  );
}
