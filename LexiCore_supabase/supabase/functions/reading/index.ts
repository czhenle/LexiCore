import OpenAI from "npm:openai";
import { standardSyllabus } from "../_shared/syllabus.ts";

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
    const syllabus = standardSyllabus(level);

    // Per LexiCore_Syllabus_Specification.md section 13: Standard <= 3 gets
    // 5 direct-retrieval questions only; Standard > 3 adds 2 KBAT questions
    // (inference/reasoning/cause-effect/interpretation/comparison) for 7
    // total. KBAT difficulty still matches Standard + ability — it does not
    // make the passage itself harder.
    const includeKbat = level > 3;
    const directCount = 5;
    const kbatCount = includeKbat ? 2 : 0;
    const totalCount = directCount + kbatCount;

    const openai = new OpenAI();

    const prompt = `
      You are an English teacher creating a reading comprehension exercise for Standard ${level} students.

      Topic: ${topic}
      Required article length: at least ${target} words
      Vocabulary difficulty: appropriate for Standard ${level} (age ${level + 6}) — ${syllabus.vocabLevel}
      Allowed grammar (Standard ${level} and everything from earlier Standards, cumulatively): ${syllabus.allowedGrammar}
      Do NOT use grammar structures that belong substantially to a later Standard.
      Passage complexity guidance: ${syllabus.readingComplexity}

      Instructions:
      1. Write a meaningful, engaging article on the topic — not a list
      2. The article must have a clear title, introduction, body paragraphs, and conclusion
      3. Use vocabulary and grammar within the allowed scope above
      4. Make it interesting and relatable for Malaysian primary school students
      5. After the article, create exactly ${directCount} DIRECT questions ("type": "direct") that are answerable straight from information stated in the passage — who/what/where/when, direct retrieval, basic vocabulary meaning${
        includeKbat
          ? `\n      6. Then create exactly ${kbatCount} KBAT questions ("type": "kbat") testing inference, reasoning, cause/effect, interpretation, applying information, or comparison — still answerable from the passage, but requiring thought beyond direct retrieval. KBAT difficulty must still match Standard ${level}.`
          : "\n      6. Do NOT include inference/KBAT questions at this Standard — keep every question direct retrieval."
      }
      7. Every question must be answerable from the passage
      8. Total questions: exactly ${totalCount}

      Return ONLY valid JSON in this exact format:
      {
        "title": "Article title",
        "body": "Full article text here, at least ${target} words. Use \\n\\n to separate paragraphs.",
        "questions": [
          {
            "question": "Question text here",
            "type": "direct",
            "options": { "A": "option", "B": "option", "C": "option", "D": "option" },
            "correct_answer": "A",
            "explanation": "Brief explanation why this answer is correct"
          }
        ]
      }`;

    // gpt-5.6-luna is a reasoning model: it rejects `temperature`, and
    // `max_tokens` would be spent on reasoning tokens before any article
    // text is emitted — so neither is set. Length is steered by the word
    // target in the prompt instead.
    const response = await openai.chat.completions.create({
      model:           "gpt-5.6-luna",
      messages:        [{ role: "user", content: prompt }],
      response_format: { type: "json_object" },
    });

    const data = JSON.parse(response.choices[0].message.content ?? "{}");
    return jsonResponse(data);

  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, 500);
  }
});
