// ============================================================================
// LexiCore — Open-Answer Grader (Supabase Edge Function, Deno)
// ----------------------------------------------------------------------------
// Judges a student's free-text response to an open-format item. Replaces the
// old self-assessment flow ("did you get it right?" asked to the student
// themselves) with an actual LLM-as-judge verdict, mirroring generate/index.ts's
// own verify() pattern.
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const {
      question,
      student_response,
      model_answer,
      explanation,
      sub_skill_name,
      target_word,
      rung,
      standard,
    } = await req.json();

    const targetLine = target_word
      ? `\nThe student's sentence MUST correctly use the target word "${target_word}" (or an equally correct word for the same idea). If they used a different, wrong word, mark it incorrect and say what the right word was.`
      : "";

    const prompt = `You are grading a Malaysian primary-school student's (Standard ${
      standard ?? "?"
    }) answer to an English question testing "${sub_skill_name ?? "English"}" (rung ${
      rung ?? "?"
    }).

Question: "${question ?? ""}"
A model answer looks like: "${model_answer ?? ""}"
${explanation ? `Why the model answer works: ${explanation}` : ""}${targetLine}

The student wrote: "${student_response ?? ""}"

Judge whether the student's answer correctly demonstrates "${sub_skill_name ?? "the skill"}" — minor spelling/punctuation slips that don't affect meaning should NOT fail it, but the core grammar/vocabulary/meaning point being tested must be right.

Respond ONLY in JSON: {"correct": boolean, "feedback": string}. "feedback" must be one short (under 30 words), warm, specific sentence — reference the student's own words when useful, and if wrong, say what to fix.`;

    const openai = new OpenAI({ apiKey: Deno.env.get("OPENAI_API_KEY") });
    // No temperature: gpt-5.6-luna is a reasoning model and rejects it.
    const r = await openai.chat.completions.create({
      model: MODEL,
      messages: [{ role: "user", content: prompt }],
      response_format: { type: "json_object" },
    });

    let verdict: { correct?: boolean; feedback?: string } = {};
    try {
      verdict = JSON.parse(r.choices[0].message.content ?? "{}");
    } catch {
      // fall through to the safe default below
    }

    if (typeof verdict.correct !== "boolean" || !verdict.feedback) {
      return json(
        {
          error: "grader produced an invalid verdict",
        },
        502,
      );
    }

    return json({ correct: verdict.correct, feedback: verdict.feedback });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return json({ error: message }, 500);
  }
});
