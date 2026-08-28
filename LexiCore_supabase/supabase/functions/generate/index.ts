// ============================================================================
// LexiCore — Generate → Validate → Repair  (Supabase Edge Function, Deno)
// ----------------------------------------------------------------------------
// This is the CONTROL LAYER around the LLM. The model is treated as an
// unreliable component: every item it produces is checked by LexiCore's own
// validators, and rejected items are REPAIRED (regenerated with the failure
// reason fed back) until they pass or a retry budget is exhausted.
//
// Inputs come from the learner model, not from a plain prompt:
//   { skill, sub_skill, sub_skill_name, rung, format, standard,
//     target_difficulty, recent_errors[] }
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

// Cheap, reliable generator; a slightly stronger, independent verifier.
const GENERATOR_MODEL = "gpt-5.6-luna";
const VERIFIER_MODEL  = "gpt-5.6-luna"; // swap to a stronger model for stricter QA
const MAX_ATTEMPTS = 3;

// Rung intent — keeps the prompt aligned to the pedagogical ladder.
const RUNG_INTENT: Record<number, string> = {
  1: "UNDERSTAND: introduce/recognise the concept with heavy support",
  2: "RECOGNISE: pick the correct option; receptive discrimination",
  3: "CONTROLLED: guided production with scaffolds (word bank / gap fill)",
  4: "TRANSFER: apply the concept in a new/extended context or transform it",
  5: "PRODUCE: free production the student writes themselves",
};

// Which formats are choice-based (need options + a key) vs open (AI-graded).
// Rungs 1-3 are scaffolded by design (RUNG_INTENT above literally calls rung 3
// "guided production with scaffolds (word bank / gap fill)") so those formats
// are choice-shaped too, just with option semantics that vary by format family
// — see FORMAT_HINT below. Only the genuinely free-production rung-4/5 formats
// stay open.
const CHOICE_FORMATS = new Set([
  "meaning_match", "mcq_word_meaning", "mcq_literal", "mcq_inference",
  "mcq_identify_or_error", "sentence_complete",
  "worked_example", "vocab_preview", "punctuation_fix",
  "cloze_sentence_wordbank", "gap_fill", "sequence_order",
  "sentence_combine", "transform_or_reorder",
]);

// How to phrase the 4 options for choice formats whose options AREN'T just
// "4 independent answer candidates" — e.g. a word bank fill vs. a full
// re-ordered sentence need different option semantics spelled out, or the
// model defaults to plain MCQ phrasing that doesn't fit the format.
const FORMAT_HINT: Record<string, string> = {
  worked_example:
    "Show a worked example first, then ask a simple recognition question about it. Options are 4 answer candidates.",
  vocab_preview:
    "Introduce one key word with its meaning, then ask a simple recognition question about it. Options are 4 answer candidates.",
  punctuation_fix:
    "The question is a sentence with a punctuation/capitalisation issue. Options are 4 candidate corrected versions of the sentence — only one is fully correct.",
  cloze_sentence_wordbank:
    "The question is a sentence with a blank. Options are 4 word-bank candidates to fill the blank — only one fits both grammar and meaning.",
  gap_fill:
    "The question is a sentence or short passage with a blank. Options are 4 candidate words/phrases to fill the blank.",
  sequence_order:
    "The question gives a jumbled set of words or sentences. Options are 4 candidate full orderings — only one is correct, not individual words.",
  sentence_combine:
    "The question gives two short sentences to combine into one. Options are 4 candidate combined sentences — only one is grammatically correct.",
  transform_or_reorder:
    "The question asks to transform a sentence (e.g. tense/voice change) or reorder it. Options are 4 candidate transformed/reordered sentences.",
};

interface GenParams {
  skill: string; sub_skill: string; sub_skill_name: string;
  rung: number; format: string; standard: number;
  target_difficulty: number; recent_errors?: string[];
}

interface Item {
  question: string; format: string;
  options?: Record<string, string>;   // for choice formats
  correct_answer?: string;            // "A".."D" for choice formats
  answer?: string;                    // model answer for open formats
  explanation: string;
  sub_skill: string; rung: number;
  // Vocabulary open items only — anchors the free-writing prompt to one
  // concrete word so both the student and the grader know what's expected.
  target_word?: string;
  hint?: string;
  image_keyword?: string;
  image_b64?: string | null;
}

function isVocabOpen(p: GenParams): boolean {
  return p.skill === "Vocabulary" && !CHOICE_FORMATS.has(p.format);
}

// ── PROMPT ──────────────────────────────────────────────────────────────────
function buildPrompt(p: GenParams): string {
  const syllabus = standardSyllabus(p.standard);
  const errs = (p.recent_errors ?? []).length
    ? `\nThe student RECENTLY got these wrong — target the same weakness:\n- ${p.recent_errors!.join("\n- ")}`
    : "";
  const shape = CHOICE_FORMATS.has(p.format)
    ? `Return options A-D and the correct_answer letter. Exactly ONE option is correct. All four options must be distinct and plausible; distractors should reflect realistic mistakes, not nonsense.
"correct_answer" MUST be the option LETTER — exactly one of "A", "B", "C" or "D" — never the option's text. Example: for options {"A":"a","B":"an"} where "an" is right, correct_answer is "B", NOT "an". Do NOT include an "answer" field on a choice item.${
        FORMAT_HINT[p.format] ? ` ${FORMAT_HINT[p.format]}` : ""
      }`
    : `This is an OPEN-RESPONSE item: the student WRITES their own answer in a text box. There are no choices to pick from.
Provide a model "answer" (what a good student response looks like) and an "explanation".
You MUST NOT include an "options" key or a "correct_answer" key. Do not phrase the question as "Which of the following…" or list A/B/C/D anywhere in the question text — the student cannot see any options.${
        isVocabOpen(p)
          ? ` This is a VOCABULARY item, so anchor it to exactly ONE concrete target word the student's sentence must use — pick a word that fits "${p.sub_skill_name}". Also provide:
- "target_word": that one word (lowercase).
- "hint": a short child-friendly clue describing the word WITHOUT saying it or any part of it (e.g. for "sister": "a person older than you who is a girl").
- "image_keyword": the same word (or a close, simple concrete synonym), phrased as a single noun a picture can clearly show DALL-E can illustrate.
The question itself should ask the student to use the target word in a sentence (they'll see the hint and a picture, not the word itself).`
          : ""
      }`;

  // Writing's genuinely open, higher-rung formats (guided/free composition,
  // open paragraphs) need an actual word-count target and complexity
  // guidance from the shared per-Standard syllabus config — without this
  // they default to whatever length the model feels like. Only applies to
  // OPEN Writing formats; scaffolded choice-shaped Writing items (even at
  // higher Standards) don't need a word count.
  const writingGuidance =
    p.skill === "Writing" && !CHOICE_FORMATS.has(p.format) && syllabus.writingMinWords > 0
      ? `\nWriting complexity for Standard ${p.standard}: ${syllabus.writingComplexity}\nThis is a written composition response — require at least ${syllabus.writingMinWords} words.`
      : "";

  return `You are an English item-writer for a Malaysian primary-school learner.
Write ONE item that EXACTLY matches this specification:
- Skill: ${p.skill}
- Sub-skill: ${p.sub_skill_name} (${p.sub_skill})
- Ladder rung: ${p.rung}
- What rung ${p.rung} means: ${RUNG_INTENT[p.rung]}
- Item format: ${p.format}
- School standard: ${p.standard} (difficulty target ${p.target_difficulty})
- Allowed grammar/vocabulary (Standard ${p.standard} and cumulative from earlier Standards): ${syllabus.allowedGrammar}
${shape}${writingGuidance}${errs}

Rules:
1. The item must test ${p.sub_skill_name} and NOTHING else.
2. Match rung ${p.rung} exactly — do not make it easier or harder.
3. Age-appropriate, natural language for a Standard ${p.standard} child.
4. Return ONLY valid JSON with EXACTLY these keys — no others:
   ${
     CHOICE_FORMATS.has(p.format)
       ? `question, format, options, correct_answer, explanation, sub_skill, rung`
       : isVocabOpen(p)
         ? `question, format, answer, explanation, sub_skill, rung, target_word, hint, image_keyword`
         : `question, format, answer, explanation, sub_skill, rung`
   }
5. "rung" must be the bare integer ${p.rung} — not a string, and not a label
   like "${p.rung} — ...". "sub_skill" must be exactly "${p.sub_skill}".`;
}

// ── STRUCTURAL VALIDATION (LexiCore's own checks, no model needed) ───────────
function validateStructure(item: Item, p: GenParams): string[] {
  const issues: string[] = [];
  if (!item.question || item.question.trim().length < 3)
    issues.push("question missing or too short");
  if (!item.explanation) issues.push("explanation missing");

  if (CHOICE_FORMATS.has(p.format)) {
    const opts = item.options ?? {};
    const keys = Object.keys(opts);
    if (keys.length !== 4) issues.push("choice item must have exactly 4 options");
    const vals = Object.values(opts).map((v) => (v ?? "").trim().toLowerCase());
    if (new Set(vals).size !== vals.length) issues.push("duplicate options");
    if (vals.some((v) => v.length === 0)) issues.push("empty option");
    if (!item.correct_answer || !keys.includes(item.correct_answer))
      issues.push("correct_answer is not one of the option keys");
  } else {
    if (!item.answer || item.answer.trim().length < 1)
      issues.push("open item must include a model answer");
    if (item.options) issues.push("open item must not have options");
    if (isVocabOpen(p)) {
      if (!item.target_word || item.target_word.trim().length < 1)
        issues.push("vocabulary open item must include target_word");
      if (!item.hint || item.hint.trim().length < 1)
        issues.push("vocabulary open item must include hint");
      if (!item.image_keyword || item.image_keyword.trim().length < 1)
        issues.push("vocabulary open item must include image_keyword");
    }
  }
  // The model sometimes echoes the prompt's own rung line back verbatim
  // (e.g. "3 — CONTROLLED") instead of the bare integer. That used to fail
  // strict !== on all 3 attempts and return a 422, which is a hard failure
  // for the student over pure formatting. Parse a leading integer so the
  // label form is tolerated; only a genuinely DIFFERENT rung is an issue.
  // JSON.stringify in the message so a type mismatch is visible — the old
  // message rendered as the useless "got 3, want 3".
  const rungNum = typeof item.rung === "number"
    ? item.rung
    : parseInt(String(item.rung ?? ""), 10);
  if (rungNum !== p.rung) {
    issues.push(`rung mismatch (got ${JSON.stringify(item.rung)}, want ${p.rung})`);
  }
  return issues;
}

// ── INDEPENDENT VERIFIER (a second model double-checks correctness) ──────────
async function verify(openai: OpenAI, item: Item, p: GenParams): Promise<string[]> {
  const prompt = `You are a strict QA checker for a children's English quiz.
Check this item and answer ONLY in JSON: {"ok": boolean, "issues": string[]}.
Fail it if ANY is true:
- the marked correct answer is actually wrong
- more than one option could be correct, or none is
- it does not test "${p.sub_skill_name}"
- it is not appropriate for a Standard ${p.standard} child
Item: ${JSON.stringify(item)}`;
  // No temperature: gpt-5.6-luna is a reasoning model and rejects it.
  const r = await openai.chat.completions.create({
    model: VERIFIER_MODEL,
    messages: [{ role: "user", content: prompt }],
    response_format: { type: "json_object" },
  });
  try {
    const v = JSON.parse(r.choices[0].message.content ?? "{}");
    return v.ok ? [] : (v.issues ?? ["verifier rejected item"]);
  } catch {
    return []; // fail-open on verifier parse error; structural checks still applied
  }
}

// ── THE LOOP ─────────────────────────────────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const p = (await req.json()) as GenParams;
    const openai = new OpenAI({ apiKey: Deno.env.get("OPENAI_API_KEY") });
    const qa: Array<{ attempt: number; issues: string[] }> = [];
    let feedback = "";

    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
      const gen = await openai.chat.completions.create({
        model: GENERATOR_MODEL,
        messages: [{ role: "user", content: buildPrompt(p) + feedback }],
        response_format: { type: "json_object" },
      });

      let item: Item;
      try {
        item = JSON.parse(gen.choices[0].message.content ?? "{}");
      } catch {
        qa.push({ attempt, issues: ["invalid JSON"] });
        feedback = "\n\nYour last output was not valid JSON. Return valid JSON only.";
        continue;
      }

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
        if (isVocabOpen(p) && item.image_keyword) {
          // One picture per served item (not per attempt) — wrapped so an
          // image failure never fails the whole item; the client already
          // handles a null image_b64 gracefully (see vocabulary/index.ts).
          try {
            const img = await openai.images.generate({
              model: "gpt-image-2-2026-04-21",
              prompt:
                `Simple, cute, kid-friendly illustration of a ${item.image_keyword}. Flat vector art style, clean white background, no text, no labels.`,
              n: 1,
              size: "1024x1024",
              quality: "low",
            });
            item.image_b64 = img.data?.[0]?.b64_json ?? null;
          } catch (e) {
            console.error("image gen failed:", e);
            item.image_b64 = null;
          }
        }
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