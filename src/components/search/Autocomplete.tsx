"use client";

import { useId, useState, type KeyboardEvent, type ReactNode } from "react";

/** Accessible combobox: text input + suggestion listbox with keyboard navigation. */
export function Autocomplete<T>({
  label, value, onInputChange, suggestions, onPick, getKey, renderItem, placeholder, icon, trailing,
  inputTestId, onEnter,
}: {
  label: string;
  value: string;
  onInputChange: (v: string) => void;
  suggestions: T[];
  onPick: (item: T) => void;
  getKey: (item: T) => string;
  renderItem: (item: T) => ReactNode;
  placeholder?: string;
  icon?: ReactNode;
  trailing?: ReactNode;
  inputTestId?: string;
  onEnter?: () => void;
}) {
  const id = useId();
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(-1);
  const show = open && suggestions.length > 0;

  function onKeyDown(e: KeyboardEvent<HTMLInputElement>) {
    if (e.key === "ArrowDown" && suggestions.length) {
      e.preventDefault();
      setOpen(true);
      setActive((i) => (i + 1) % suggestions.length);
    } else if (e.key === "ArrowUp" && suggestions.length) {
      e.preventDefault();
      setActive((i) => (i <= 0 ? suggestions.length - 1 : i - 1));
    } else if (e.key === "Enter") {
      if (show && active >= 0) {
        e.preventDefault();
        onPick(suggestions[active]);
        setOpen(false);
      } else {
        setOpen(false);
        onEnter?.();
      }
    } else if (e.key === "Escape") {
      setOpen(false);
    }
  }

  return (
    <div className="relative min-w-0 flex-1">
      <label htmlFor={id} className="block px-1 text-[11px] font-semibold uppercase tracking-wide text-stone-500">
        {label}
      </label>
      <div className="flex items-center gap-2">
        {icon && <span className="text-stone-400" aria-hidden>{icon}</span>}
        <input
          id={id}
          role="combobox"
          aria-expanded={show}
          aria-controls={`${id}-list`}
          aria-autocomplete="list"
          aria-activedescendant={show && active >= 0 ? `${id}-opt-${active}` : undefined}
          autoComplete="off"
          data-testid={inputTestId}
          className="w-full min-w-0 bg-transparent py-1 text-base text-stone-900 outline-none placeholder:text-stone-400"
          placeholder={placeholder}
          value={value}
          onChange={(e) => {
            onInputChange(e.target.value);
            setOpen(true);
            setActive(-1);
          }}
          onFocus={() => setOpen(true)}
          onBlur={() => setTimeout(() => setOpen(false), 150)}
          onKeyDown={onKeyDown}
        />
        {trailing}
      </div>
      {show && (
        <ul
          id={`${id}-list`}
          role="listbox"
          className="absolute left-0 right-0 top-full z-[1100] mt-2 max-h-72 overflow-auto rounded-xl border border-stone-200 bg-white py-1 shadow-lg"
        >
          {suggestions.map((s, i) => (
            <li
              key={getKey(s)}
              id={`${id}-opt-${i}`}
              role="option"
              aria-selected={i === active}
              className={`cursor-pointer px-3 py-2 text-sm ${i === active ? "bg-orange-50" : "hover:bg-stone-50"}`}
              onMouseDown={(e) => {
                e.preventDefault();
                onPick(s);
                setOpen(false);
              }}
            >
              {renderItem(s)}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
