import { HomeSearch } from "@/components/search/HomeSearch";

export default function Home() {
  return (
    <main>
      <section className="bg-gradient-to-b from-orange-100 via-amber-50 to-stone-50">
        <div className="mx-auto max-w-5xl px-4 pb-16 pt-14 md:pt-24">
          <h1 className="text-4xl font-extrabold tracking-tight text-stone-900 md:text-6xl">
            Find a dish near you.
          </h1>
          <p className="mt-3 max-w-2xl text-lg text-stone-700">
            Home cooks around you are making biryani, tacos, dumplings and more — some of it is on the stove right now.
          </p>
          <div className="mt-8">
            <HomeSearch />
          </div>
        </div>
      </section>
    </main>
  );
}
