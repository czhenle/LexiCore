import OpenAI from "npm:openai";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status,
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const body = await req.json();
    const {
      standard, detected_level, study_time, strength, weakness,
      vocab_score, grammar_score, reading_score, writing_score,
      modifier,
    } = body;

    const openai = new OpenAI();

    // Build modifier instruction
    const modifierInstructions: Record<string, string> = {
      more:     "INCREASE the number of daily tasks and add more challenging exercises. The student wants to grow faster.",
      less:     "REDUCE the number of daily tasks. The student finds the current plan too heavy.",
      shorten:  "Keep the same topics but REDUCE the time per task to make sessions shorter.",
      lengthen: "Keep the same topics but INCREASE the time per task — the student has more time available.",
    };
    const modifierNote = modifier && modifierInstructions[modifier]
      ? `\n\nIMPORTANT ADJUSTMENT: ${modifierInstructions[modifier]}`
      : "";

    const prompt = `
      You are an expert English curriculum planner for Malaysian primary school students (KSSR syllabus).

      Student profile:
      - School standard: ${standard}
      - Detected ability level: ${detected_level}
      - Daily study time: ${study_time}
      - Strongest skill: ${strength}
      - Weakest skill: ${weakness}
      - Scores — Vocabulary: ${vocab_score}%, Grammar: ${grammar_score}%, Reading: ${reading_score}%, Writing: ${writing_score}%
      ${modifierNote}

      Create a structured 4-week English learning plan:
      1. Allocate MORE time to the weakest skill (${weakness})
      2. Build on the strongest skill (${strength}) with advanced tasks
      3. Follow KSSR progression: simple → complex
      4. Daily tasks must fit within ${study_time} per day
      5. Use specific topics, not vague descriptions

      Return ONLY valid JSON:
      {
        "summary": "One sentence describing this personalised plan",
        "weeks": [
          {
            "week": 1,
            "focus": "Main focus for this week",
            "daily_tasks": [
              { "day": "Monday",    "skill": "Grammar",    "task": "Specific task", "duration": "15 mins" },
              { "day": "Tuesday",   "skill": "Vocabulary", "task": "Specific task", "duration": "15 mins" },
              { "day": "Wednesday", "skill": "Reading",    "task": "Specific task", "duration": "15 mins" },
              { "day": "Thursday",  "skill": "Writing",    "task": "Specific task", "duration": "15 mins" },
              { "day": "Friday",    "skill": "Grammar",    "task": "Specific task", "duration": "15 mins" }
            ]
          }
        ]
      }`;

    const response = await openai.chat.completions.create({
      model:           "gpt-4o-mini",
      messages:        [{ role: "user", content: prompt }],
      response_format: { type: "json_object" },
      temperature:     0.7,
    });

    const plan = JSON.parse(
      response.choices[0].message.content ?? "{}"
    );
    return jsonResponse(plan);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, 500);
  }
});