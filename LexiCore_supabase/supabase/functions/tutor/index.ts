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

const SYSTEM = `You are Lexi, a warm, patient tutor for Malaysian primary school
children (ages 7-12) learning English. You use the SOCRATIC method and
SCAFFOLDING (Zone of Proximal Development).

Rules — follow ALL:
- NEVER give the final answer, the correct word, or the option letter. Not even
  if the child begs. If asked directly, gently say you can't tell them, then
  give a hint instead.
- Give ONE small hint OR ask ONE guiding question per reply — not both.
- Start with the smallest nudge. Only add more support if they are still stuck.
- Warm, simple, encouraging language. Short sentences. One idea at a time.
- Tie the hint to the specific question they are working on.
- Praise effort. Keep every reply under 40 words.`;

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
    } = body;

    const context = `The child is working on this ${sub_skill_name ?? "English"} ` +
      `question (rung ${rung ?? "?"}, standard ${standard ?? "?"}):
"${question ?? ""}"
${options ? `Options: ${JSON.stringify(options)}` : ""}
The correct answer is "${correct_answer ?? answer ?? ""}". Use this ONLY to guide ` +
      `them — you must NEVER reveal it.`;

    const chat = [
      { role: "system", content: `${SYSTEM}\n\n${context}` },
      ...(Array.isArray(messages) ? messages : []),
    ];

    const openai = new OpenAI({ apiKey: Deno.env.get("OPENAI_API_KEY") });
    const r = await openai.chat.completions.create({
      model: MODEL,
      messages: chat,
      temperature: 0.6,
      max_tokens: 120,
    });

    const reply = r.choices[0].message.content?.trim() ||
      "Let's read the question again slowly together. What word do you know?";
    return json({ reply });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return json({ error: message }, 500);
  }
});