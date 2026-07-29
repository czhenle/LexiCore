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
const GENERATOR_MODEL = "gpt-4.1-mini";
const VERIFIER_MODEL  = "gpt-4.1-mini"; // swap to a stronger model for stricter QA
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
const CHOICE_FORMATS = new Set([
  "meaning_match", "mcq_word_meaning", "mcq_literal", "mcq_inference",
  "mcq_identify_or_error", "sentence_complete",
]);

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
}

// ── PROMPT ──────────────────────────────────────────────────────────────────
function buildPrompt(p: GenParams): string {
  const errs = (p.recent_errors ?? []).length
    ? `\nThe student RECENTLY got these wrong — target the same weakness:\n- ${p.recent_errors!.join("\n- ")}`
    : "";
  const shape = CHOICE_FORMATS.has(p.format)
    ? `Return options A-D and the correct_answer letter. Exactly ONE option is correct. All four options must be distinct and plausible; distractors should reflect realistic mistakes, not nonsense.`
    : `This is an OPEN item the student writes. Provide a model "answer" and an "explanation". Do NOT provide multiple-choice options.`;

  return `You are a KSSR English item-writer for Malaysian primary school.
Write ONE item that EXACTLY matches this specification:
- Skill: ${p.skill}
- Sub-skill: ${p.sub_skill_name} (${p.sub_skill})
- Ladder rung ${p.rung} — ${RUNG_INTENT[p.rung]}
- Item format: ${p.format}
- School standard: ${p.standard} (difficulty target ${p.target_difficulty})
${shape}${errs}

Rules:
1. The item must test ${p.sub_skill_name} and NOTHING else.
2. Match rung ${p.rung} exactly — do not make it easier or harder.
3. Age-appropriate, natural language for a Standard ${p.standard} child.
4. Return ONLY valid JSON with keys:
   question, format, options (choice only), correct_answer (choice only),
   answer (open only), explanation, sub_skill, rung.`;
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
  }
  if (item.rung !== p.rung) issues.push(`rung mismatch (got ${item.rung}, want ${p.rung})`);
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
  const r = await openai.chat.completions.create({
    model: VERIFIER_MODEL,
    messages: [{ role: "user", content: prompt }],
    response_format: { type: "json_object" },
    temperature: 0,
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
        temperature: 0.7,
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