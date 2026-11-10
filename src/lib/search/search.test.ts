import { describe, expect, it } from "vitest";
import {
  convertRadius,
  defaultUnitForLocales,
  formatDistance,
  regionFromLocale,
  suggestExpandedRadius,
  toMeters,
} from "./units";
import { currencyForLocales, formatPriceWithApprox } from "./currency";
import {
  defaultSearchState,
  parseSearchParams,
  radiusMeters,
  toRpcFilters,
  toSearchParams,
} from "./params";

describe("units", () => {
  it("picks miles for US/UK and km elsewhere", () => {
    expect(defaultUnitForLocales(["en-US"])).toBe("mi");
    expect(defaultUnitForLocales(["en-GB"])).toBe("mi");
    expect(defaultUnitForLocales(["en-CA"])).toBe("km");
    expect(defaultUnitForLocales(["bn-BD"])).toBe("km");
    expect(defaultUnitForLocales(["en", "en-GB"])).toBe("mi"); // first locale WITH a region
    expect(defaultUnitForLocales(["fr"])).toBe("km");
  });

  it("parses regions", () => {
    expect(regionFromLocale("zh-Hant-TW")).toBe("TW");
    expect(regionFromLocale("en_GB")).toBe("GB");
    expect(regionFromLocale("en")).toBeNull();
    expect(regionFromLocale("not a locale")).toBeNull();
  });

  it("converts radii", () => {
    expect(toMeters(5, "mi")).toBe(8047);
    expect(toMeters(5, "km")).toBe(5000);
    expect(convertRadius(5, "mi", "km")).toBe(8);
    expect(convertRadius(10, "km", "mi")).toBe(6);
    expect(convertRadius(100, "mi", "km")).toBe(100); // clamped
  });

  it("formats privacy-rounded distances", () => {
    expect(formatDistance(2.4, "mi")).toBe("2.4 mi away");
    expect(formatDistance(0, "km")).toBe("0.1 km away");
  });

  it("suggests the next preset that reaches the nearest match", () => {
    expect(suggestExpandedRadius(5, toMeters(7.2, "mi"), "mi")).toBe(10);
    expect(suggestExpandedRadius(3, toMeters(3.7, "mi"), "mi")).toBe(5);
    expect(suggestExpandedRadius(50, toMeters(80, "mi"), "mi")).toBe(100);
    expect(suggestExpandedRadius(5, null, "mi")).toBeNull();
    expect(suggestExpandedRadius(100, toMeters(120, "mi"), "mi")).toBeNull();
  });
});

describe("currency", () => {
  it("derives the buyer currency from the locale", () => {
    expect(currencyForLocales(["en-GB"])).toBe("GBP");
    expect(currencyForLocales(["de-DE"])).toBe("EUR");
    expect(currencyForLocales(["bn-BD"])).toBe("BDT");
    expect(currencyForLocales(["en"])).toBe("USD");
  });

  it("only shows an approximation when currencies differ", () => {
    expect(formatPriceWithApprox(1600, "USD", 1600, "USD", "en-US")).toEqual({ local: "$16", approx: null });
    const r = formatPriceWithApprox(45000, "BDT", 374, "USD", "en-US");
    expect(r.local).toContain("450");
    expect(r.approx).toBe("≈ $3.74");
  });
});

describe("URL state", () => {
  it("round-trips through URL params", () => {
    const state = {
      ...defaultSearchState("mi"),
      q: "biryani",
      lat: 40.7549,
      lng: -73.984,
      loc: "Midtown, New York",
      r: 10,
      sort: "rating" as const,
      view: "map" as const,
      cuisines: ["indian"],
      diet: ["halal" as const],
      priceMax: 20,
      minRating: 4.5,
      fulfillment: "delivery" as const,
      availableNow: true,
      deliverToMe: true,
    };
    const qs = toSearchParams(state).toString();
    expect(qs).toContain("q=biryani");
    expect(qs).toContain("lat=40.75490");
    expect(qs).toContain("r=10");
    expect(qs).toContain("unit=mi");
    expect(parseSearchParams(new URLSearchParams(qs))).toEqual(state);
  });

  it("matches the spec example", () => {
    const s = parseSearchParams(new URLSearchParams("?q=biryani&lat=23.81&lng=90.41&r=10&unit=mi"));
    expect(s).toMatchObject({ q: "biryani", lat: 23.81, lng: 90.41, r: 10, unit: "mi" });
    expect(radiusMeters(s)).toBe(16093);
  });

  it("rejects junk instead of throwing", () => {
    const s = parseSearchParams(
      new URLSearchParams("lat=999&lng=abc&r=-4&unit=parsecs&sort=drop&diet=halal,plutonium&fulfil=teleport"),
      defaultSearchState("km"),
    );
    expect(s.lat).toBeNull();
    expect(s.lng).toBeNull();
    expect(s.unit).toBe("km");
    expect(s.r).toBe(5);
    expect(s.sort).toBe("nearest");
    expect(s.diet).toEqual(["halal"]);
    expect(s.fulfillment).toBeNull();
  });

  it("clamps the radius to the slider range", () => {
    expect(parseSearchParams(new URLSearchParams("r=500")).r).toBe(100);
    expect(parseSearchParams(new URLSearchParams("r=0.4")).r).toBe(1);
  });

  it("builds RPC filters", () => {
    const f = toRpcFilters(
      { ...defaultSearchState("km"), diet: ["vegan"], priceMin: 2, deliverToMe: true },
      "GBP",
    );
    expect(f).toEqual({ currency: "GBP", unit: "km", diet: ["vegan"], price_min: 2, deliver_to_me: true });
  });
});
