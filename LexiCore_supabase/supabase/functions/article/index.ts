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

// Word count targets per level
const wordTargets: Record<number, number> = {
  1: 60, 2: 160, 3: 260, 4: 360, 5: 460, 6: 560,
};

const topics = [
  "School life", "Family and home", "Animals in Malaysia",
  "Food and cooking", "Festivals in Malaysia", "The environment",
  "Sports and games", "Community helpers", "Technology",
  "Travel and places", "Health and the body", "Hobbies",
];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const { detected_level = 3 } = await req.json();
    const level   = Math.min(Math.max(Number(detected_level), 1), 6);
    const target  = wordTargets[level] ?? 260;
    const topic   = topics[Math.floor(Math.random() * topics.length)];

    const openai = new OpenAI();

    const prompt = `
      You are writing an English reading article for a Malaysian primary school student at Standard ${level} level.

      Topic: ${topic}
      Word count: at least ${target} words
      Vocabulary difficulty: appropriate for Standard ${level} (age ${level + 6})

      Rules:
      1. Write a meaningful, engaging article — not a simple list
      2. Use vocabulary that a Standard ${level} student is learning or should learn
      3. Include 5–8 interesting vocabulary words naturally in the article
      4. The article must be coherent, have an introduction, body, and conclusion
      5. Write in clear, simple English appropriate for the level
      6. Make it culturally relevant to Malaysia where possible

      Return ONLY valid JSON in this exact format:
      {
        "title": "Article title here",
        "topic": "${topic}",
        "body": "Full article text here, at least ${target} words, with natural paragraphs separated by \\n\\n",
        "hints": [
          { "word": "vocabulary word", "meaning": "simple definition a student would understand" },
          { "word": "vocabulary word", "meaning": "simple definition" }
        ]
      }`;

    const response = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [{ role: "user", content: prompt }],
      response_format: { type: "json_object" },
      temperature: 0.8,
    });

    const article = JSON.parse(
      response.choices[0].message.content ?? "{}"
    );
    return jsonResponse(article);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, 500);
  }
});