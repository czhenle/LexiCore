// Strips markdown emphasis/headers/code-ticks and literal escaped-newline
// sequences the model sometimes emits inside a JSON string value (e.g.
// "**Spring**\n\n" showing up verbatim to the student — Flutter's Text()
// renders whatever string it gets, it doesn't parse markdown). Applied as a
// safety net to every free-text field a generated item can carry,
// regardless of what the prompt itself says — see generate/index.ts and
// grade/index.ts's own prompt instructions for the first line of defense.
export function sanitizeText<T extends string | null | undefined>(s: T): T {
  if (s == null) return s;
  return s
    // Literal backslash+n (two characters), NOT an actual newline — happens
    // when the model double-escapes inside its own JSON string, so the
    // parsed value still contains a visible "\n" instead of a real line
    // break. Real newlines are left alone — the passage's own body
    // deliberately uses them for paragraph breaks, and Flutter's Text()
    // renders those correctly; this only targets the broken case.
    .replace(/\\n+/g, " ")
    // Markdown emphasis/bold/italic/code markers, keeping the inner text.
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/__([^_]+)__/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    // Leftover stray markers not part of a matched pair (odd number of *,
    // unmatched #, etc.) — just drop them, they're never meaningful text.
    // Deliberately NOT stripping underscores here — gap_fill/cloze/
    // vocab_context_mcq questions use runs of underscores ("___") as the
    // actual blank the student fills in; only a genuine markdown-italic
    // *pair* (`_word_`, handled by the model rarely using single
    // underscores this way) would need stripping, and isn't worth the risk
    // of nuking every blank in the app to catch it.
    .replace(/[*`#]+/g, "")
    // Collapse whitespace runs left behind by the above.
    .replace(/[ \t]+/g, " ")
    .trim() as T;
}

// Runs sanitizeText over every known free-text field on a generated item
// (or a passage-shaped {title, body} object) — mutates and returns the same
// object for convenient chaining at the call site.
export function sanitizeItem<T extends Record<string, unknown>>(item: T): T {
  const textKeys = [
    "question", "explanation", "answer", "context_text", "hint",
    "target_word", "image_keyword", "title", "body",
  ];
  for (const k of textKeys) {
    if (typeof item[k] === "string") {
      (item as Record<string, unknown>)[k] = sanitizeText(item[k] as string);
    }
  }
  const options = item.options as Record<string, string> | null | undefined;
  if (options && typeof options === "object") {
    for (const k of Object.keys(options)) {
      if (typeof options[k] === "string") options[k] = sanitizeText(options[k]) as string;
    }
  }
  if (Array.isArray(item.hints)) {
    item.hints = (item.hints as unknown[]).map((h) =>
      typeof h === "string" ? sanitizeText(h) : h
    );
  }
  if (Array.isArray(item.word_bank)) {
    item.word_bank = (item.word_bank as unknown[]).map((w) =>
      typeof w === "string" ? sanitizeText(w) : w
    );
  }
  if (Array.isArray(item.explanation_breakdown)) {
    item.explanation_breakdown = (
      item.explanation_breakdown as Array<Record<string, unknown>>
    ).map((e) => ({
      ...e,
      label: typeof e.label === "string" ? sanitizeText(e.label) : e.label,
      note: typeof e.note === "string" ? sanitizeText(e.note) : e.note,
    }));
  }
  return item;
}
