// ============================================================================
// LexiCore — Generate → Validate → Repair  (Supabase Edge Function, Deno)
// ----------------------------------------------------------------------------
// This is the CONTROL LAYER around the LLM. The model is treated as an
// unreliable component: every item it produces is checked by LexiCore's own
// validators, and rejected items are REPAIRED (regenerated with the failure
// reason fed back) until they pass or a retry budget is exhausted.
//
// Skill-agnostic engine only — everything specific to a skill's own formats
// (which are choice vs open, per-format prompt hints, extra required keys/
// validation, post-processing like Vocabulary's DALL-E step) lives in
// ../_shared/generators/{skill}.ts and is dispatched to by MODULES below.
//
// Inputs come from the learner model, not from a plain prompt:
//   { skill, sub_skill, sub_skill_name, rung, format, standard,
//     target_difficulty, recent_errors[], recent_questions[], context_passage? }
//
// The function returns the first item that passes, plus a `qa` log of every
// attempt — feed that log into your generation-accuracy evaluation.
//
// Contribution framing (for the viva): the LLM writes text; LexiCore decides
// the target (learner model), grounds the request (curriculum + past errors),
// and ENFORCES correctness (structural checks + an independent verifier model).
// ============================================================================

import OpenAI from "npm:openai";
import { standardSyllabus } from "../_shared/syllabus.ts";
import { vocabularyModule } from "../_shared/generators/vocabulary.ts";
import { grammarModule } from "../_shared/generators/grammar.ts";
import { readingModule } from "../_shared/generators/reading.ts";
import { writingModule } from "../_shared/generators/writing.ts";
import type { GenParams, Item, SkillModule } from "../_shared/generators/types.ts";
import { sanitizeItem, sanitizeText } from "../_shared/sanitize.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status,
  });
}

// Generator writes content under a lot of stacked constraints at once (rung
// intent, exact sub-skill, format shape, syllabus-derived CEFR/vocab/grammar
// bounds, and — in batch mode — holding all of that consistent across
// several items in one response), so it gets the stronger model. Verifier
// only checks the result against fixed rules (rung match, structural shape,
// answer validity) — narrower and far higher-frequency (runs on every item,
// sometimes several times across repair attempts), so it stays on the
// cheaper model.
const GENERATOR_MODEL = "gpt-5.6-terra";
const VERIFIER_MODEL  = "gpt-5.6-luna";
const MAX_ATTEMPTS = 3;
// Neither call needs deep multi-step reasoning — both are constrained,
// well-scoped tasks (fixed schema / a clear rubric to check against), not
// open-ended problems. Cuts latency substantially vs. the unset default.
// The verifier's job (spot obvious errors) is simpler than the generator's
// (write a good item), so it gets an even lower effort setting.
const GENERATOR_EFFORT = "low";
const VERIFIER_EFFORT = "none";

const MODULES: Record<string, SkillModule> = {
  Vocabulary: vocabularyModule,
  Grammar: grammarModule,
  Reading: readingModule,
  Writing: writingModule,
};

// Rung intent — keeps the prompt aligned to the pedagogical ladder. Note:
// for Vocabulary's mode-based formats (vocab_image_mcq, etc.) the FORMAT is
// chosen by the client (which mode-card was tapped), not derived from rung
// the way every other skill's ladder works — rung there only scales
// difficulty within whichever mode is active.
const RUNG_INTENT: Record<number, string> = {
  1: "UNDERSTAND: introduce/recognise the concept with heavy support",
  2: "RECOGNISE: pick the correct option; receptive discrimination",
  3: "CONTROLLED: guided production with scaffolds (word bank / gap fill)",
  4: "TRANSFER: apply the concept in a new/extended context or transform it",
  5: "PRODUCE: free production the student writes themselves",
};

function moduleFor(p: GenParams): SkillModule {
  return MODULES[p.skill] ?? grammarModule;
}

function isChoice(p: GenParams): boolean {
  return moduleFor(p).choiceFormats.has(p.format);
}

// ── PROMPT ──────────────────────────────────────────────────────────────────
function buildPrompt(p: GenParams): string {
  const mod = moduleFor(p);
  const syllabus = standardSyllabus(p.standard);
  const errs = (p.recent_errors ?? []).length
    ? `\nThe student RECENTLY got these wrong — target the same weakness:\n- ${p.recent_errors!.join("\n- ")}`
    : "";
  const repeats = (p.recent_questions ?? []).length
    ? `\nThe student has ALREADY been asked these recently on this sub-skill — write a genuinely DIFFERENT question, not a reworded copy:\n- ${p.recent_questions!.join("\n- ")}`
    : "";
  const shape = isChoice(p)
    ? `Return options A-D and the correct_answer letter. Exactly ONE option is correct. All four options must be distinct and plausible; distractors should reflect realistic mistakes, not nonsense.
"correct_answer" MUST be the option LETTER — exactly one of "A", "B", "C" or "D" — never the option's text. Example: for options {"A":"a","B":"an"} where "an" is right, correct_answer is "B", NOT "an". Do NOT include an "answer" field on a choice item.${
        mod.formatHint(p.format) ? ` ${mod.formatHint(p.format)}` : ""
      }`
    : `This is an OPEN-RESPONSE item: the student WRITES their own answer in a text box. There are no choices to pick from.
Provide a model "answer" (what a good student response looks like) and an "explanation".
You MUST NOT include an "options" key or a "correct_answer" key. Do not phrase the question as "Which of the following…" or list A/B/C/D anywhere in the question text — the student cannot see any options.${mod.openExtra(p, syllabus)}`;

  const passageGuidance = p.context_passage
    ? `\nBase this question on the EXACT passage below — do not invent a new passage or reference anything not in it:\n"""\n${p.context_passage}\n"""`
    : "";

  const extraKeys = mod.requiredKeysExtra(p);
  const baseKeys = isChoice(p)
    ? ["question", "format", "options", "correct_answer", "explanation", "sub_skill", "rung"]
    : ["question", "format", "answer", "explanation", "sub_skill", "rung"];

  return `You are an English item-writer for a Malaysian primary-school learner.
Write ONE item that EXACTLY matches this specification:
- Skill: ${p.skill}
- Sub-skill: ${p.sub_skill_name} (${p.sub_skill})
- Ladder rung: ${p.rung}
- What rung ${p.rung} means: ${RUNG_INTENT[p.rung]}
- Item format: ${p.format}
- School standard: ${p.standard} (difficulty target ${p.target_difficulty})
- Allowed grammar/vocabulary (Standard ${p.standard} and cumulative from earlier Standards): ${syllabus.allowedGrammar}
${shape}${passageGuidance}${errs}${repeats}

Rules:
1. The item must test ${p.sub_skill_name} and NOTHING else.
2. Match rung ${p.rung} exactly — do not make it easier or harder.
3. Age-appropriate, natural language for a Standard ${p.standard} child.
4. Return ONLY valid JSON with EXACTLY these keys — no others:
   ${[...baseKeys, ...extraKeys].join(", ")}
5. "rung" must be the bare integer ${p.rung} — not a string, and not a label
   like "${p.rung} — ...". "sub_skill" must be exactly "${p.sub_skill}".
6. Plain text only in every field — no markdown (no **, #, backticks) and no
   literal \\n line breaks; write real sentences with real spaces.
7. Keep "question" to ONLY the instruction/question itself — never combine it
   with other fields' content (a word bank, a context sentence, the options)
   as one paragraph. For a choice item, do NOT restate the 4 options as prose
   or a "Word bank: ..." list inside "question" — they are already shown to
   the student separately; write "question" as if the options were invisible
   to you.`;
}

// Cheap safety net for stray case/whitespace on the answer letter itself
// (e.g. "a" or " A" instead of "A") — kept even though it turned out NOT to
// be the main cause of "correct_answer is not one of the option keys" (see
// normalizeOptionKeys below for the real one); harmless either way.
function normalizeCorrectAnswer(item: Item): void {
  if (typeof item.correct_answer === "string") {
    item.correct_answer = item.correct_answer.trim().toUpperCase();
  }
}

// The REAL cause of "correct_answer is not one of the option keys" being the
// single most common batch-generation rejection: a live re-test with the
// actual received values logged showed the batch path occasionally emits
// "options" keyed by "0"/"1"/"2"/"3" instead of the required "A"/"B"/"C"/
// "D" — while "correct_answer" is still a proper letter. The batch prompt's
// choice-shape instructions never showed a concrete JSON example (the
// single-item prompt does), which likely explains why only batch calls
// drifted this way — now fixed prompt-side too, but this stays as a
// defensive remap regardless. JS guarantees ascending numeric enumeration
// order for integer-like string keys, so re-keying 0/1/2/3 -> A/B/C/D in
// that same order preserves which option is which — confirmed against every
// sample from the re-test (e.g. correct_answer "A" + 0-indexed options
// always landed on the grammatically correct option after remapping).
function normalizeOptionKeys(item: Item): void {
  const opts = item.options;
  if (!opts || typeof opts !== "object") return;
  const keys = Object.keys(opts);
  if (keys.length !== 4) return;
  const zeroIndexed = keys.every((k, i) => k === String(i));
  const oneIndexed = keys.every((k, i) => k === String(i + 1));
  if (!zeroIndexed && !oneIndexed) return;

  const letters = ["A", "B", "C", "D"];
  const sourceKeys = zeroIndexed ? ["0", "1", "2", "3"] : ["1", "2", "3", "4"];
  const remapped: Record<string, string> = {};
  sourceKeys.forEach((k, i) => { remapped[letters[i]] = (opts as Record<string, string>)[k]; });

  // correct_answer was a bare digit in the same indexing scheme (rare, but
  // symmetric with the options bug) — convert it too; otherwise it's
  // already a proper letter and needs no change.
  if (typeof item.correct_answer === "string") {
    const idx = sourceKeys.indexOf(item.correct_answer.trim());
    if (idx !== -1) item.correct_answer = letters[idx];
  }
  item.options = remapped;
}

// ── STRUCTURAL VALIDATION (LexiCore's own checks, no model needed) ───────────
function validateStructure(item: Item, p: GenParams): string[] {
  const mod = moduleFor(p);
  const issues: string[] = [];
  if (!item.question || item.question.trim().length < 3)
    issues.push("question missing or too short");
  if (!item.explanation) issues.push("explanation missing");

  if (isChoice(p)) {
    const opts = item.options ?? {};
    const keys = Object.keys(opts);
    if (keys.length !== 4) issues.push("choice item must have exactly 4 options");
    const vals = Object.values(opts).map((v) => (v ?? "").trim().toLowerCase());
    if (new Set(vals).size !== vals.length) issues.push("duplicate options");
    if (vals.some((v) => v.length === 0)) issues.push("empty option");
    if (!item.correct_answer || !keys.includes(item.correct_answer)) {
      // Diagnostic: the normalized-casing fix (trim+uppercase) didn't
      // change how often this fires in a live re-test, so the cause isn't
      // simple case/whitespace drift — surfacing the actual received
      // value (and the option keys/values it's being checked against)
      // instead of guessing again.
      issues.push(
        `correct_answer is not one of the option keys (got: ${JSON.stringify(item.correct_answer)}, keys: ${JSON.stringify(keys)}, options: ${JSON.stringify(opts)})`,
      );
    }
  } else {
    if (!item.answer || item.answer.trim().length < 1)
      issues.push("open item must include a model answer");
    if (item.options) issues.push("open item must not have options");
  }
  issues.push(...mod.validateExtra(item, p));

  // The model sometimes echoes the prompt's own rung line back verbatim
  // (e.g. "3 — CONTROLLED") instead of the bare integer. That used to fail
  // strict !== on all 3 attempts and return a 422, which is a hard failure
  // for the student over pure formatting. Parse a leading integer so the
  // label form is tolerated; only a genuinely DIFFERENT rung is an issue.
  const rungNum = typeof item.rung === "number"
    ? item.rung
    : parseInt(String(item.rung ?? ""), 10);
  if (rungNum !== p.rung) {
    issues.push(`rung mismatch (got ${JSON.stringify(item.rung)}, want ${p.rung})`);
  }
  return issues;
}

// ── READING PASSAGE (one per session, reused via context_passage) ───────────
// Not a question item — `format: "passage"` short-circuits the normal
// per-item loop below. Ports reading/index.ts's passage-writing prompt
// (word-count target, vocabLevel, allowedGrammar, readingComplexity from the
// syllabus) without its bundled questions, since those now come one at a
// time from the normal loop, grounded in this passage via `context_passage`.
// No repair loop — a passage has no options/correct_answer to get wrong, so
// a single attempt is enough; the client already has its own retry button.
const READING_TOPICS = [
  "School Life", "Family and Home", "Animals in Malaysia", "Food and Cooking",
  "Festivals in Malaysia", "The Environment", "Sports and Games",
  "Community Helpers", "Hobbies", "Friendship", "Nature", "Weather",
];

async function generatePassage(p: GenParams, openai: OpenAI): Promise<Response> {
  const syllabus = standardSyllabus(p.standard);
  const topic = (p as unknown as { topic?: string }).topic ||
    READING_TOPICS[Math.floor(Math.random() * READING_TOPICS.length)];
  const { minWords, targetWords, maxWords } = syllabus.reading;

  const prompt = `You are an English teacher writing a reading comprehension passage for a Malaysian Standard ${p.standard} student.
Topic: ${topic}
Required length: approximately ${targetWords} words (between ${minWords} and ${maxWords}).
Vocabulary difficulty: ${syllabus.vocabLevel}
Allowed grammar (Standard ${p.standard} and everything cumulative from earlier Standards): ${syllabus.allowedGrammar}
Passage complexity guidance: ${syllabus.readingComplexity}

Write a meaningful, engaging passage on the topic — not a list of facts. It must have a clear beginning, middle and end, using vocabulary and grammar within the allowed scope. Make it interesting and relatable for Malaysian primary school students. Do NOT include any questions, exercises, or explanations — the passage text only. Plain text — no markdown formatting (no **, #, backticks) anywhere in the title or body.

Return ONLY valid JSON: {"title": "Passage title", "body": "Full passage text, using \\n\\n between paragraphs."}`;

  const gen = await openai.chat.completions.create({
    model: GENERATOR_MODEL,
    messages: [{ role: "user", content: prompt }],
    response_format: { type: "json_object" },
    reasoning_effort: GENERATOR_EFFORT,
  } as OpenAI.Chat.ChatCompletionCreateParamsNonStreaming);

  try {
    const parsed = JSON.parse(gen.choices[0].message.content ?? "{}");
    if (typeof parsed.title !== "string" || typeof parsed.body !== "string" || !parsed.body.trim()) {
      return json({ passage: null, error: "invalid passage shape" }, 422);
    }
    return json({
      passage: {
        title: sanitizeText(parsed.title.trim()),
        body: sanitizeText(parsed.body.trim()),
      },
    });
  } catch {
    return json({ passage: null, error: "invalid JSON from model" }, 422);
  }
}

// ── INDEPENDENT VERIFIER (a second model double-checks correctness) ──────────
// vocab_context_mcq/vocab_synonyms_mcq deliberately ask the generator for
// near-synonym distractors (that's the whole pedagogical point — a student
// has to discriminate between "quiet" and "silent", not just spot an
// unrelated word) — but the verifier's own "more than one option could be
// correct" rule, taken literally, flags exactly that on nearly every item,
// since a near-synonym often IS "also somewhat correct" in isolation. That
// contradiction was starving these two formats' batches down to 0 valid
// items after all 3 retries (the 422 "cannot prepare the question" the
// student was seeing). Softened here: the verifier still fails a genuinely
// ambiguous item, it just no longer treats "the distractor is a synonym" by
// itself as proof of ambiguity for the formats designed to use them.
function NEAR_SYNONYM_NOTE(format: string): string {
  if (format !== "vocab_context_mcq" && format !== "vocab_synonyms_mcq") return "";
  return `\nNote: this format DELIBERATELY uses near-synonym distractors the student must discriminate between (e.g. "quiet" vs "silent", "small" vs "tiny") — that is the intended difficulty, not a flaw. Do NOT fail an item just because a distractor is "also a synonym" or "could also fit in a different sentence" in the abstract. Only fail it if, given THIS EXACT item (its context sentence or definition), the distractor is EQUALLY correct — a fair-minded English teacher marking this specific item would genuinely accept it too, not merely find it related.`;
}

// These formats carry an "image_keyword" that only becomes an actual
// picture AFTER verification passes (postProcess's DALL-E call runs on the
// way out, not before) — so at the point the verifier sees the item, the
// image genuinely does not exist yet. A live test run showed the verifier
// correctly noticing this and then, unhelpfully, rejecting the item over
// it ("no picture is provided, so it cannot be verified") — true, but not
// a real defect in the item, since nothing could ever satisfy that check
// at this stage. Told explicitly here so it judges everything else about
// the item instead.
const IMAGE_DEPENDENT_FORMATS = new Set([
  "vocab_image_mcq", "vocab_image_open", "vocab_spelling_open", "guided_composition",
]);
function IMAGE_NOTE(p: GenParams): string {
  const isImageDependent = IMAGE_DEPENDENT_FORMATS.has(p.format) ||
    (p.format === "open_sentence" && p.skill === "Vocabulary");
  if (!isImageDependent) return "";
  return `\nNote: this item comes with a picture (described by its "image_keyword") that has NOT been generated yet at this point — you will only ever see the text fields, never the actual image. Do NOT fail an item just because "no picture is provided" or "the image cannot be verified" — that is expected and true of every item in this format, not a defect in this one. Judge everything else about the item (the question text, the answer, whether image_keyword itself is a clear, sensible, age-appropriate concrete noun/scene) as normal.`;
}

async function verify(openai: OpenAI, item: Item, p: GenParams): Promise<string[]> {
  const passageContext = p.context_passage
    ? `\nThe item is supposed to be grounded in this exact passage — you HAVE been given it, so check the item actually matches it, don't complain that it's missing:\n"""\n${p.context_passage}\n"""`
    : "";
  const prompt = `You are a strict QA checker for a children's English quiz.
Check this item and answer ONLY in JSON: {"ok": boolean, "issues": string[]}.
Fail it if ANY is true:
- the marked correct answer is actually wrong
- more than one option could be correct, or none is
- it does not test "${p.sub_skill_name}"
- it is not appropriate for a Standard ${p.standard} child${passageContext}${NEAR_SYNONYM_NOTE(p.format)}${IMAGE_NOTE(p)}
Item: ${JSON.stringify(item)}`;
  // No temperature: gpt-5.6-luna is a reasoning model and rejects it.
  const r = await openai.chat.completions.create({
    model: VERIFIER_MODEL,
    messages: [{ role: "user", content: prompt }],
    response_format: { type: "json_object" },
    reasoning_effort: VERIFIER_EFFORT,
  } as OpenAI.Chat.ChatCompletionCreateParamsNonStreaming);
  try {
    const v = JSON.parse(r.choices[0].message.content ?? "{}");
    return v.ok ? [] : (v.issues ?? ["verifier rejected item"]);
  } catch {
    return []; // fail-open on verifier parse error; structural checks still applied
  }
}

// ── BATCH GENERATION ──────────────────────────────────────────────────────
// A separate path from the single-item loop below, dispatched only when the
// caller passes count > 1 — used ONLY for confirmation windows (adaptive_
// practice_screen.dart), where the next several items are ALREADY known to
// share the same rung/format before any of them are answered, since rung is
// held fixed for the whole window by construction. The single-item loop
// below is completely untouched by any of this, so nothing that doesn't
// pass count keeps behaving exactly as it always has.
function buildBatchPrompt(p: GenParams, count: number): string {
  const mod = moduleFor(p);
  const syllabus = standardSyllabus(p.standard);
  const errs = (p.recent_errors ?? []).length
    ? `\nThe student RECENTLY got these wrong — target the same weakness:\n- ${p.recent_errors!.join("\n- ")}`
    : "";
  const repeats = (p.recent_questions ?? []).length
    ? `\nThe student has ALREADY been asked these recently on this sub-skill — every new item must be GENUINELY DIFFERENT, not a reworded copy:\n- ${p.recent_questions!.join("\n- ")}`
    : "";
  const shape = isChoice(p)
    ? `Each item returns options A-D and the correct_answer letter. Exactly ONE option is correct per item. All four options must be distinct and plausible; distractors should reflect realistic mistakes, not nonsense.
"options" MUST be a JSON object keyed by the LETTERS "A", "B", "C", "D" — e.g. {"A":"a","B":"an","C":"the","D":"some"} — NEVER by the numbers "0"/"1"/"2"/"3". "correct_answer" MUST be the option LETTER — exactly one of "A", "B", "C" or "D" — never the option's text or a number. Every item in the batch follows this same lettered shape, not just the first one. Do NOT include an "answer" key on a choice item.${
        mod.formatHint(p.format) ? ` ${mod.formatHint(p.format)}` : ""
      }`
    : `Each item is an OPEN-RESPONSE item: the student WRITES their own answer in a text box. There are no choices to pick from.
Every item needs a model "answer" (what a good student response looks like) and an "explanation".
Items MUST NOT include an "options" key or a "correct_answer" key. Do not phrase any question as "Which of the following…" or list A/B/C/D — the student cannot see any options.${mod.openExtra(p, syllabus)}`;

  const passageGuidance = p.context_passage
    ? `\nBase EVERY item on the EXACT passage below — do not invent a new passage or reference anything not in it:\n"""\n${p.context_passage}\n"""`
    : "";

  const extraKeys = mod.requiredKeysExtra(p);
  const baseKeys = isChoice(p)
    ? ["question", "format", "options", "correct_answer", "explanation", "sub_skill", "rung"]
    : ["question", "format", "answer", "explanation", "sub_skill", "rung"];

  return `You are an English item-writer for a Malaysian primary-school learner.
Write ${count} DISTINCT items that EACH exactly match this specification — same skill/level for every one, but genuinely different questions from each other, not variations of the same one:
- Skill: ${p.skill}
- Sub-skill: ${p.sub_skill_name} (${p.sub_skill})
- Ladder rung: ${p.rung}
- What rung ${p.rung} means: ${RUNG_INTENT[p.rung]}
- Item format: ${p.format}
- School standard: ${p.standard} (difficulty target ${p.target_difficulty})
- Allowed grammar/vocabulary (Standard ${p.standard} and cumulative from earlier Standards): ${syllabus.allowedGrammar}
${shape}${passageGuidance}${errs}${repeats}

Rules:
1. Every item must test ${p.sub_skill_name} and NOTHING else.
2. Match rung ${p.rung} exactly for every item — do not make any easier or harder.
3. Age-appropriate, natural language for a Standard ${p.standard} child.
4. Return ONLY valid JSON: {"items": [ ... ]} — an array of EXACTLY ${count} objects, each with EXACTLY these keys, no others:
   ${[...baseKeys, ...extraKeys].join(", ")}
5. Every item's "rung" must be the bare integer ${p.rung} — not a string, not a label. Every item's "sub_skill" must be exactly "${p.sub_skill}".
6. Plain text only in every field — no markdown (no **, #, backticks) and no
   literal \\n line breaks; write real sentences with real spaces.
7. Keep "question" to ONLY the instruction/question itself — never combine it
   with other fields' content (a word bank, a context sentence, the options)
   as one paragraph. For a choice item, do NOT restate the 4 options as prose
   or a "Word bank: ..." list inside "question" — they are already shown to
   the student separately; write "question" as if the options were invisible
   to you.`;
}

async function verifyBatch(openai: OpenAI, items: Item[], p: GenParams): Promise<string[][]> {
  const passageContext = p.context_passage
    ? `\nEvery item is supposed to be grounded in this exact passage — you HAVE been given it, so check each one actually matches it, don't complain that it's missing:\n"""\n${p.context_passage}\n"""`
    : "";
  const prompt = `You are a strict QA checker for a children's English quiz.
Check EACH of these ${items.length} items independently and answer ONLY in JSON: {"results": [{"ok": boolean, "issues": string[]}, ...]} — one result per item, in the SAME order.
Fail an item if ANY is true for it:
- the marked correct answer is actually wrong
- more than one option could be correct, or none is
- it does not test "${p.sub_skill_name}"
- it is not appropriate for a Standard ${p.standard} child${passageContext}${NEAR_SYNONYM_NOTE(p.format)}${IMAGE_NOTE(p)}
Items: ${JSON.stringify(items)}`;
  const r = await openai.chat.completions.create({
    model: VERIFIER_MODEL,
    messages: [{ role: "user", content: prompt }],
    response_format: { type: "json_object" },
    reasoning_effort: VERIFIER_EFFORT,
  } as OpenAI.Chat.ChatCompletionCreateParamsNonStreaming);
  try {
    const v = JSON.parse(r.choices[0].message.content ?? "{}");
    const results = Array.isArray(v.results) ? v.results : [];
    return items.map((_, i) => {
      const res = results[i];
      if (!res) return []; // fail-open per item if the shape doesn't line up
      return res.ok ? [] : (res.issues ?? ["verifier rejected item"]);
    });
  } catch {
    return items.map(() => []); // fail-open on verifier parse error
  }
}

async function generateBatch(p: GenParams, count: number, openai: OpenAI): Promise<Response> {
  const qa: Array<{ attempt: number; issues: string[] }> = [];
  let feedback = "";

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    const gen = await openai.chat.completions.create({
      model: GENERATOR_MODEL,
      messages: [{ role: "user", content: buildBatchPrompt(p, count) + feedback }],
      response_format: { type: "json_object" },
      reasoning_effort: GENERATOR_EFFORT,
    } as OpenAI.Chat.ChatCompletionCreateParamsNonStreaming);

    let items: Item[];
    try {
      const parsed = JSON.parse(gen.choices[0].message.content ?? "{}");
      items = Array.isArray(parsed.items) ? parsed.items : [];
    } catch {
      qa.push({ attempt, issues: ["invalid JSON"] });
      feedback = "\n\nYour last output was not valid JSON. Return valid JSON only.";
      continue;
    }
    items.forEach(normalizeOptionKeys);
    items.forEach(normalizeCorrectAnswer);

    if (items.length !== count) {
      qa.push({ attempt, issues: [`expected ${count} items, got ${items.length}`] });
      feedback = `\n\nYour previous output did not contain exactly ${count} items — return exactly {"items": [...]} with ${count} entries.`;
      continue;
    }

    const structuralIssues = items.map((item) => validateStructure(item, p));
    const verifierIssues = await verifyBatch(openai, items, p);
    const combined = items.map((_, i) => [...structuralIssues[i], ...verifierIssues[i]]);
    const anyFailed = combined.some((issues) => issues.length > 0);
    qa.push({ attempt, issues: combined.flat() });

    if (!anyFailed) {
      const mod = moduleFor(p);
      for (const item of items) {
        item.rung = p.rung;
        item.sub_skill = p.sub_skill;
        item.format = p.format;
        if (mod.postProcess) await mod.postProcess(item, p, openai);
        sanitizeItem(item as unknown as Record<string, unknown>);
      }
      return json({ items, qa, attempts: attempt }); // PASSED
    }
    feedback = `\n\nSome of your previous items FAILED checks — fix them:\n${
      combined.map((issues, i) => (issues.length ? `Item ${i + 1}: ${issues.join("; ")}` : ""))
        .filter(Boolean).join("\n")
    }`;
  }

  return json({ items: [], qa, attempts: MAX_ATTEMPTS, error: "no valid items produced" }, 422);
}

// ── THE LOOP ─────────────────────────────────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const p = (await req.json()) as GenParams & { count?: number };
    const openai = new OpenAI({ apiKey: Deno.env.get("OPENAI_API_KEY") });
    if (p.format === "passage") return await generatePassage(p, openai);
    const count = Math.max(1, Math.min(Math.trunc(p.count ?? 1) || 1, 5));
    if (count > 1) return await generateBatch(p, count, openai);
    const qa: Array<{ attempt: number; issues: string[] }> = [];
    let feedback = "";

    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
      const gen = await openai.chat.completions.create({
        model: GENERATOR_MODEL,
        messages: [{ role: "user", content: buildPrompt(p) + feedback }],
        response_format: { type: "json_object" },
        reasoning_effort: GENERATOR_EFFORT,
      } as OpenAI.Chat.ChatCompletionCreateParamsNonStreaming);

      let item: Item;
      try {
        item = JSON.parse(gen.choices[0].message.content ?? "{}");
      } catch {
        qa.push({ attempt, issues: ["invalid JSON"] });
        feedback = "\n\nYour last output was not valid JSON. Return valid JSON only.";
        continue;
      }
      normalizeOptionKeys(item);
      normalizeCorrectAnswer(item);

      const issues = [
        ...validateStructure(item, p),
        ...(await verify(openai, item, p)),
      ];
      qa.push({ attempt, issues });

      if (issues.length === 0) {
        // Normalise the fields LexiCore already knows authoritatively, so the
        // client never has to trust the model's echo of them.
        item.rung = p.rung;
        item.sub_skill = p.sub_skill;
        item.format = p.format;
        const mod = moduleFor(p);
        if (mod.postProcess) await mod.postProcess(item, p, openai);
        sanitizeItem(item as unknown as Record<string, unknown>);
        return json({ item, qa, attempts: attempt }); // PASSED
      }
      // REPAIR: feed the exact failures back into the next generation.
      feedback = `\n\nYour previous item FAILED these checks — fix them:\n- ${issues.join("\n- ")}`;
    }

    // Exhausted the retry budget — report transparently rather than shipping junk.
    return json({ item: null, qa, attempts: MAX_ATTEMPTS, error: "no valid item produced" }, 422);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return json({ error: message }, 500);
  }
});
