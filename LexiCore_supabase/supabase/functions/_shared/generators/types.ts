// ============================================================================
// Shared types + the per-skill module contract that generate/index.ts's
// engine dispatches to. Each skill module owns everything specific to that
// skill's formats; the engine owns everything skill-agnostic (the request
// loop, structural checks common to every format, the independent verifier,
// the response shape).
// ============================================================================

export interface GenParams {
  skill: string; sub_skill: string; sub_skill_name: string;
  rung: number; format: string; standard: number;
  target_difficulty: number; recent_errors?: string[];
  // Anti-repetition — recent question texts for this sub-skill, same spirit
  // as recent_errors: told to the model as "don't repeat these".
  recent_questions?: string[];
  // Grounds the item in an existing passage (guided comprehension, Reading's
  // per-session passage) instead of inventing a fresh one each call.
  context_passage?: string;
}

export interface Item {
  question: string; format: string;
  options?: Record<string, string> | null;
  correct_answer?: string | null;
  answer?: string | null;
  explanation: string;
  explanation_breakdown?: Array<{ option: string; label: string; note: string }>;
  sub_skill: string; rung: number;
  // Vocabulary open items only.
  target_word?: string; hint?: string; image_keyword?: string; image_b64?: string | null;
  // Vocabulary's vocab_context_mcq/cloze_sentence_wordbank formats only —
  // the sentence-with-blank itself, kept separate from `question` (which is
  // just the short instruction) so the client can render them as distinct
  // lines instead of one crammed-together paragraph.
  context_text?: string;
  // Vocabulary's cloze_sentence_wordbank format only — the word choices,
  // shown by the client as its own row of chips between the instruction and
  // the sentence. Never restated as prose inside `question`.
  word_bank?: string[];
  // Writing's guided_composition (a few short guiding phrases, e.g. "buying
  // food", "pay money") and free_composition (a couple of loose topic
  // categories the student could choose to write about) — plural and
  // distinct from the single `hint` above.
  hints?: string[];
}

export interface SkillModule {
  /** Formats for this skill that are choice-shaped (options + correct_answer). */
  choiceFormats: Set<string>;
  /** Per-format phrasing hint appended to the choice-item framing, "" if none. */
  formatHint(format: string): string;
  /** Extra instructions appended to the open-item framing, "" if none. */
  openExtra(p: GenParams, syllabus: unknown): string;
  /** Extra required JSON keys (rule 4) beyond the universal open-item set. */
  requiredKeysExtra(p: GenParams): string[];
  /** Extra structural validation beyond the universal checks. */
  validateExtra(item: Item, p: GenParams): string[];
  /** Optional post-pass mutation on a PASSED item (e.g. Vocabulary's DALL-E image). */
  postProcess?(item: Item, p: GenParams, openai: import("npm:openai").default): Promise<void>;
}
