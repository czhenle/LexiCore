// ============================================================================
// LexiCore — Socratic Tutor (Supabase Edge Function, Deno)  — PS3
// ----------------------------------------------------------------------------
// A hint-only tutor grounded in the EXACT item the child is stuck on plus their
// level. It never reveals the answer — it scaffolds toward it (Vygotsky's Zone
// of Proximal Development; Wood, Bruner & Ross 1976 on scaffolding). The known
// correct answer is passed in ONLY so the tutor can steer without disclosing.
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

const MODEL = "gpt-5.6-luna";

// After this many hint requests on the SAME question, the tutor is allowed
// to stop scaffolding and just give the answer — a real child who has
// genuinely tried several times and is still stuck needs relief, not a 4th
// nudge, and endless withholding reads as unhelpful rather than pedagogical.
// hint_count is the number of the child's asks INCLUDING this one (see
// tutor_sheet.dart), so a threshold of 3 means: still-scaffolds on asks 1-2,
// reveals on ask 3 onward.
const LENIENCY_THRESHOLD = 3;

const SYSTEM = `You are Lexi, a warm, patient tutor for Malaysian primary school
children (ages 7-12) learning English. You use the SOCRATIC method and
SCAFFOLDING (Zone of Proximal Development).

Rules — follow ALL:
- NEVER give the final answer, the correct word, or the option letter. Not even
  if the child begs. If asked directly, gently say you can't tell them, then
  give a hint instead.
- Give ONE small hint OR ask ONE guiding question per reply — not both. Put
  whichever one you're giving in the matching JSON field below and leave the
  other field as an empty string.
- Start with the smallest nudge. Only add more support if they are still stuck.
- Warm, simple, encouraging language. Short sentences. One idea at a time.
- Tie the hint to the specific question they are working on.
- Praise effort. Keep every reply under 40 words.
- Leave "answer" as an empty string.

Respond ONLY in JSON: {"type": "guiding_hint", "hint": string, "question": string, "answer": string}
— this matches the same typed reply shape LexiCore's chatbot uses, so the
client can render both through one shared component.`;

const LENIENT_SYSTEM = `You are Lexi, a warm, patient tutor for Malaysian primary school
children (ages 7-12) learning English. You use the SOCRATIC method and
SCAFFOLDING (Zone of Proximal Development).

This child has already asked for help several times on this SAME question and
is still stuck — that's genuine effort, not laziness. Rules for THIS reply
only — follow ALL:
- Warmly acknowledge their effort in one short sentence.
- Give them the correct answer plainly, put it in the "answer" field (the
  exact word/option/sentence they need — not a paraphrase).
- Then, in 1-2 short sentences, explain briefly WHY it's correct, so they
  still learn something — put this explanation in "hint".
- Leave "question" as an empty string.
- Warm, simple, encouraging language. Keep the whole reply under 50 words.

Respond ONLY in JSON: {"type": "reveal_answer", "hint": string, "question": string, "answer": string}`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const body = await req.json();
    const {
      question,
      options,
      correct_answer,
      answer,
      sub_skill_name,
      rung,
      standard,
      messages,
      hint_count,
    } = body;

    const lenient = (typeof hint_count === "number" ? hint_count : 0) >= LENIENCY_THRESHOLD;
    const trueAnswer = correct_answer ?? answer ?? "";

    const context = `The child is working on this ${sub_skill_name ?? "English"} ` +
      `question (rung ${rung ?? "?"}, standard ${standard ?? "?"}):
"${question ?? ""}"
${options ? `Options: ${JSON.stringify(options)}` : ""}
The correct answer is "${trueAnswer}".` +
      (lenient
        ? " The child has asked for help several times — see this reply's rules."
        : " Use this ONLY to guide them — you must NEVER reveal it.");

    const chat = [
      { role: "system", content: `${lenient ? LENIENT_SYSTEM : SYSTEM}\n\n${context}` },
      ...(Array.isArray(messages) ? messages : []),
    ];

    const openai = new OpenAI({ apiKey: Deno.env.get("OPENAI_API_KEY") });
    // gpt-5.6-luna is a reasoning model: `temperature` is rejected, and the
    // old `max_tokens: 120` cap would be consumed by reasoning tokens before
    // any hint text was produced — yielding an empty reply. The "under 40
    // words" rule in SYSTEM keeps replies short instead. Low reasoning
    // effort — a single scaffolded nudge doesn't need deep reasoning, and
    // this cuts latency substantially.
    const r = await openai.chat.completions.create({
      model: MODEL,
      messages: chat,
      response_format: { type: "json_object" },
      reasoning_effort: "low",
    } as OpenAI.Chat.ChatCompletionCreateParamsNonStreaming);

    const raw = r.choices[0].message.content ?? "{}";
    let reply: { type?: string; hint?: string; question?: string; answer?: string } = {};
    try {
      reply = JSON.parse(raw);
    } catch {
      // fall through to the fallback below
    }
    if (!reply || typeof reply !== "object" || (!reply.hint && !reply.question && !reply.answer)) {
      // Even the fallback respects leniency — a stuck child on their 3rd+ ask
      // shouldn't have a parse hiccup cost them the promised reveal.
      reply = lenient
        ? {
            type: "reveal_answer",
            hint: "You've worked hard on this one!",
            question: "",
            answer: trueAnswer,
          }
        : {
            type: "guiding_hint",
            hint: "Let's read the question again slowly together. What word do you know?",
            question: "",
            answer: "",
          };
    } else {
      reply.type = reply.answer ? "reveal_answer" : "guiding_hint";
      reply.hint = reply.hint ?? "";
      reply.question = reply.question ?? "";
      reply.answer = reply.answer ?? "";
    }

    return json({ reply });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return json({ error: message }, 500);
  }
});