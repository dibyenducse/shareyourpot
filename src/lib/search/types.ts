export type DistanceUnit = "mi" | "km";

export type SortOption = "nearest" | "best_match" | "rating" | "price_asc" | "ready_soonest";

export type ViewMode = "list" | "map";

export type Fulfillment = "pickup" | "delivery";

export const DIET_FLAGS = [
  { value: "halal", label: "Halal" },
  { value: "vegetarian", label: "Vegetarian" },
  { value: "vegan", label: "Vegan" },
  { value: "gluten_free", label: "Gluten-free" },
  { value: "kosher", label: "Kosher" },
  { value: "dairy_free", label: "Dairy-free" },
  { value: "nut_free", label: "Nut-free" },
] as const;

export type DietFlag = (typeof DIET_FLAGS)[number]["value"];

export const SORT_OPTIONS: { value: SortOption; label: string }[] = [
  { value: "nearest", label: "Nearest" },
  { value: "best_match", label: "Best match" },
  { value: "rating", label: "Rating" },
  { value: "price_asc", label: "Price: low to high" },
  { value: "ready_soonest", label: "Ready soonest" },
];

/** Everything that defines a search. Serialised 1:1 into the URL. */
export interface SearchState {
  q: string;
  lat: number | null;
  lng: number | null;
  /** Human label for the location ("Brooklyn, NY" / "Current location"). */
  loc: string;
  /** Radius in `unit`. */
  r: number;
  unit: DistanceUnit;
  sort: SortOption;
  view: ViewMode;
  cuisines: string[];
  diet: DietFlag[];
  priceMin: number | null;
  priceMax: number | null;
  minRating: number | null;
  fulfillment: Fulfillment | null;
  availableNow: boolean;
  deliverToMe: boolean;
}

/** A row returned by the `search_dishes` RPC. */
export interface DishResult {
  result_type: "cooking_now" | "kitchen_card";
  id: string;
  cook_id: string;
  cook_name: string;
  cook_avatar_url: string | null;
  cook_rating: number;
  cook_rating_count: number;
  title: string;
  title_local: string | null;
  description: string | null;
  photo_url: string | null;
  cuisine: string | null;
  category: string | null;
  diet_flags: string[];
  price_cents: number;
  currency: string;
  buyer_price_cents: number | null;
  buyer_currency: string;
  /** Rounded to 0.1 of `distance_unit` (privacy). */
  distance_m: number;
  distance: number;
  distance_unit: DistanceUnit;
  /** Fuzzed public point (never the cook's real location). */
  approx_lat: number;
  approx_lng: number;
  approx_radius_m: number;
  is_live: boolean;
  ready_at: string | null;
  available_until: string | null;
  portions_left: number | null;
  prep_time_minutes: number | null;
  pickup_available: boolean;
  delivery_available: boolean;
  can_deliver: boolean;
  match_score: number;
  total_count: number;
}

export interface SearchFallback {
  nearest_match_m: number | null;
  similar: DishResult[];
}
