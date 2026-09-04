// ============================================================================
// LexiCore — Study Schedule Personalizer (Supabase Edge Function, Deno)
// ----------------------------------------------------------------------------
// The actual SCHEDULE (which skill/sub-skill lands on which day, where the
// Weekly Assessment/rest days go, week boundaries) is decided entirely by
// deterministic logic in the client's MasteryService.generateStudyPlan() —
// that stays rule-based on purpose, since it's driven by the same mastery
// state the Elo engine maintains, and must always work even if this call
// fails or the network is down.
//
// This function does ONE narrow thing: given the plan LexiCore already
// decided (as short template strings), rewrite the day task_labels, week
// milestones, and the overall plan_goal into warmer, more personalised
// wording for the child's Standard — same facts (same skill/sub-skill names,
// same days), nicer phrasing. It never chooses what goes on what day.
//
// Caller MUST treat every field of the response as optional/best-effort and
// fall back to its own template string per-item if a key is missing/empty —
// this endpoint enhances wording, it is never load-bearing for the plan to
// exist or be correct.
// ============================================================================

import OpenAI from "npm:openai";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};
function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status,
  });
}

const MODEL = "gpt-5.6-terra";

// Keep the payload (and the model's job) small — cap how many day/week
// entries get sent even if a caller passes a long plan.
const MAX_DAYS = 30;
const MAX_WEEKS = 5;

const SYSTEM = `You are Lexi, a warm, encouraging English tutor for Malaysian
primary school children. LexiCore's own logic has already decided a study
plan — which skill and sub-skill go on which day, and each week's focus. Your
ONLY job is to rewrite the provided template labels into short, warm,
encouraging wording for a Standard-appropriate child. Do NOT change what is
being studied, invent new sub-skills, or reorder anything — only reword.

Rules:
- Plain text only. No markdown (**, #, backticks), no literal "\\n" sequences.
- British English spelling (colour, favourite, organise).
- Each day_label: under 10 words, still clearly names the sub-skill.
- Each week milestone: 1-2 short sentences, warm and motivating, mentions the
  sub-skills actually touched that week.
- plan_goal: one short, encouraging sentence.
- Return JSON with EXACTLY the same date keys (day_labels) and week_number
  keys (week_milestones) you were given — never add, drop, or rename keys.

Respond ONLY as JSON: {"plan_goal": string, "day_labels": {"<date>": string},
"week_milestones": {"<week_number>": string}}`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const body = await req.json();
    const {
      standard = 3,
      weakest_skill = "",
      plan_goal_template = "",
      days = [],
      weeks = [],
    } = body;

    const dayList = (Array.isArray(days) ? days : []).slice(0, MAX_DAYS);
    const weekList = (Array.isArray(weeks) ? weeks : []).slice(0, MAX_WEEKS);

    // Nothing worth personalising — hand back an empty best-effort shape
    // rather than spending an OpenAI call on it.
    if (dayList.length === 0 && weekList.length === 0 && !plan_goal_template) {
      return json({ plan_goal: "", day_labels: {}, week_milestones: {} });
    }

    const userPayload = {
      standard,
      weakest_skill,
      plan_goal_template,
      days: dayList,
      weeks: weekList,
    };

    const openai = new OpenAI({ apiKey: Deno.env.get("OPENAI_API_KEY") });
    const r = await openai.chat.completions.create({
      model: MODEL,
      messages: [
        { role: "system", content: SYSTEM },
        { role: "user", content: JSON.stringify(userPayload) },
      ],
      response_format: { type: "json_object" },
      reasoning_effort: "low",
    } as OpenAI.Chat.ChatCompletionCreateParamsNonStreaming);

    const raw = r.choices[0].message.content ?? "{}";
    let parsed: any = {};
    try {
      parsed = JSON.parse(raw);
    } catch {
      parsed = {};
    }

    // Best-effort, per-item shape — caller is expected to fall back to its
    // own template per key if something here is missing or malformed, so we
    // don't need to validate strictly here; just make sure the top-level
    // shape is sane.
    const plan_goal = typeof parsed.plan_goal === "string" ? parsed.plan_goal : "";
    const day_labels =
      parsed.day_labels && typeof parsed.day_labels === "object" ? parsed.day_labels : {};
    const week_milestones =
      parsed.week_milestones && typeof parsed.week_milestones === "object"
        ? parsed.week_milestones
        : {};

    return json({ plan_goal, day_labels, week_milestones });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("schedule error:", message);
    // Best-effort endpoint — an error here should never surface as a scary
    // failure to the child; caller falls back to its own template strings.
    return json({ plan_goal: "", day_labels: {}, week_milestones: {} }, 200);
  }
});
