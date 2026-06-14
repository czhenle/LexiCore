import OpenAI from "npm:openai";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status,
  });
}

// Word count targets per level (KSSR aligned)
const wordTargets: Record<number, number> = {
  1: 60, 2: 160, 3: 260, 4: 360, 5: 460, 6: 560,
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { standard = 3, topic = "A Short Story" } = await req.json();
    const level  = Math.min(Math.max(Number(standard), 1), 6);
    const target = wordTargets[level] ?? 260;

    const openai = new OpenAI();

    const prompt = `
      You are a KSSR English Teacher creating a reading comprehension exercise for Standard ${level} students.

      Topic: ${topic}
      Required article length: at least ${target} words
      Vocabulary difficulty: appropriate for Standard ${level} (age ${level + 6})

      Instructions:
      1. Write a meaningful, engaging article on the topic — not a list
      2. The article must have a clear title, introduction, body paragraphs, and conclusion
      3. Use vocabulary appropriate for Standard ${level}
      4. Make it interesting and relatable for Malaysian primary school students
      5. After the article, create 5 reading comprehension multiple-choice questions
      6. Questions must be based ONLY on information in the article
      7. Include inference questions (not just literal recall)

      Return ONLY valid JSON in this exact format:
      {
        "title": "Article title",
        "body": "Full article text here, at least ${target} words. Use \\n\\n to separate paragraphs.",
        "questions": [
          {
            "question": "Question text here",
            "options": { "A": "option", "B": "option", "C": "option", "D": "option" },
            "correct_answer": "A",
            "explanation": "Brief explanation why this answer is correct"
          }
        ]
      }`;

    const response = await openai.chat.completions.create({
      model:           "gpt-4o-mini",
      messages:        [{ role: "user", content: prompt }],
      response_format: { type: "json_object" },
      temperature:     0.7,
      max_tokens:      2000,
    });

    const data = JSON.parse(response.choices[0].message.content ?? "{}");
    return jsonResponse(data);

  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, 500);
  }
});