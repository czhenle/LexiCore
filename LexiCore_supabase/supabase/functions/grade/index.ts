// ============================================================================
// LexiCore — Open-Answer Grader (Supabase Edge Function, Deno)
// ----------------------------------------------------------------------------
// Judges a student's free-text response to an open-format item. Replaces the
// old self-assessment flow ("did you get it right?" asked to the student
// themselves) with an actual LLM-as-judge verdict, mirroring generate/index.ts's
// own verify() pattern.
//
// Also grades Writing's composition submissions, either typed (student_response)
// or a photo of handwriting (image) — the same multimodal `input_image` +
// responses.create pattern already proven in chatbot/index.ts, just wired to
// grading instead of tutoring. Both paths return the same {correct, feedback,
// word_count, mistakes} shape; word_count/mistakes are optional additions that
// existing callers (adaptive practice's open items, the assessment's guided
// comprehension) simply don't request/use.
// ============================================================================

import OpenAI from "npm:openai";
import { sanitizeText } from "../_shared/sanitize.ts";

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
      image,
      min_words,
      format,
    } = await req.json();

    // Spelling items INVERT the usual leniency. For every other open item, a
    // spelling slip that doesn't change the meaning should be forgiven — you
    // don't fail a child for a typo when the item is testing past tense. But
    // when spelling IS the skill, "buterfly" is simply wrong, and the generic
    // rubric below was passing it (confirmed live: correct:true alongside a
    // mistakes entry spelling out the very error).
    const isSpelling = String(format ?? "") === "vocab_spelling_open";

    const targetLine = target_word
      ? `\nThe student's sentence MUST correctly use the target word "${target_word}" (or an equally correct word for the same idea). If they used a different, wrong word, mark it incorrect and say what the right word was.`
      : "";

    // min_words is only ever sent for Writing's composition tasks (guided/
    // free composition) — every other open item (a one-sentence vocab
    // answer, a grammar transform, ...) omits it. Used as the same signal
    // here to ask for a full corrected essay back, since that's only
    // meaningful for a multi-sentence composition, not a single-line answer.
    const isEssay = !!min_words;

    const wordCountLine = min_words
      ? `\nCount the words in the student's response and return it as "word_count". The student was asked for at least ${min_words} words — a SMALL shortfall (a handful of words under) shouldn't be treated as a failure on its own, just reflect it fairly in "feedback"/"model_essay"; only note it as a "mistake" if they fell well short. Always grade the writing quality itself on its own merits regardless of length.`
      : `\nReturn "word_count": null (word count isn't relevant for this item).`;

    const essayLine = isEssay
      ? `\nAlso write "model_essay": a corrected, polished version of the STUDENT'S OWN essay — keep their ideas, content and structure, but fix every grammar/vocabulary/spelling mistake and improve word choice where it clearly helps, so the student can directly compare their original writing to a strong, correct version of what THEY wrote (not a generic unrelated example, and not a totally different essay). Keep it close to their original length. If their response was empty or unusable, return "model_essay": null instead.`
      : `\nReturn "model_essay": null (not relevant for this item).`;

    const instructions = `You are grading a Malaysian primary-school student's (Standard ${
      standard ?? "?"
    }) answer to an English question testing "${sub_skill_name ?? "English"}" (rung ${
      rung ?? "?"
    }).

Question: "${question ?? ""}"
A model answer looks like: "${model_answer ?? ""}"
${explanation ? `Why the model answer works: ${explanation}` : ""}${targetLine}
${wordCountLine}${essayLine}

${
      isSpelling
        ? `This is a SPELLING item: the student heard the word and typed how they think it is spelled. Spelling IS the skill being tested here, so "correct" is true ONLY if their spelling matches "${model_answer ?? ""}" exactly (ignoring surrounding spaces and capitalisation). A single wrong or missing letter is incorrect, however close it looks. Still be warm about it and point out exactly which letters were wrong.`
        : `Judge whether the response correctly demonstrates "${sub_skill_name ?? "the skill"}" — minor spelling/punctuation slips that don't affect meaning should NOT fail it, but the core grammar/vocabulary/meaning point being tested must be right.`
    }

Respond ONLY in JSON: {"correct": boolean, "feedback": string, "word_count": number|null, "mistakes": string[], "model_essay": string|null}.
- "feedback": one short (under 30 words), warm, encouraging recommendation on how to improve — reference the student's own words when useful.
- "mistakes": a short array (0-5 items) of SPECIFIC errors found (grammar, spelling, word choice) — empty array if there are none worth mentioning. Still fill this in even when "model_essay" is also provided — mistakes is the quick list, model_essay is the full corrected read.
- Plain text only — no markdown (no **, #, backticks) and no literal \\n line breaks anywhere.`;

    const openai = new OpenAI({ apiKey: Deno.env.get("OPENAI_API_KEY") });
    let raw: string;

    if (image) {
      // Photo of handwriting — same input_image + responses.create pattern
      // already proven in chatbot/index.ts. The model transcribes first,
      // then grades the transcription; only the JSON fields above matter.
      const imageDataUrl = String(image).startsWith("data:")
        ? String(image)
        : `data:image/jpeg;base64,${image}`;
      const r = await openai.responses.create({
        model: MODEL,
        instructions: `${instructions}\n\nThe student's response is a PHOTO of their handwritten answer — read it as carefully as you can before grading. If it's illegible in places, do your best and don't penalise handwriting neatness itself, only the English.`,
        input: [
          {
            role: "user",
            content: [
              {
                type: "input_text",
                // Responses API's json_object format requires the word
                // "json" to literally appear somewhere in the input.
                text: (student_response
                  ? `The student also typed this alongside the photo: "${student_response}"`
                  : "Please read and grade the photo of my handwritten answer.") +
                  "\n\n(Reply as JSON.)",
              },
              { type: "input_image", image_url: imageDataUrl },
            ],
          },
        ] as any,
        reasoning: { effort: "medium" },
        text: { format: { type: "json_object" } },
      });
      raw = (r.output_text as string | undefined)?.trim() ?? "{}";
    } else {
      // No temperature: gpt-5.6-terra is a reasoning model and rejects it.
      // MEDIUM reasoning effort: raised from "low" because marking a child's
      // free-text answer fairly (partial credit, near-misses, the intent
      // behind a clumsy sentence) is a judgement call, not a lookup.
      const r = await openai.chat.completions.create({
        model: MODEL,
        messages: [
          {
            role: "user",
            content: `${instructions}\n\nThe student wrote: "${student_response ?? ""}"`,
          },
        ],
        response_format: { type: "json_object" },
        reasoning_effort: "medium",
      } as OpenAI.Chat.ChatCompletionCreateParamsNonStreaming);
      raw = r.choices[0].message.content ?? "{}";
    }

    let verdict: {
      correct?: boolean;
      feedback?: string;
      word_count?: number | null;
      mistakes?: string[];
      model_essay?: string | null;
    } = {};
    try {
      verdict = JSON.parse(raw);
    } catch {
      // fall through to the invalid-verdict response below
    }

    if (typeof verdict.correct !== "boolean" || !verdict.feedback) {
      return json({ error: "grader produced an invalid verdict" }, 502);
    }

    // Whether a word is spelled correctly is a string comparison, not a
    // judgement call — so don't leave it to the model's discretion even with
    // the rubric above. Anything else would let a wrong spelling raise the
    // student's mastery score for the very skill they just got wrong.
    let correct = verdict.correct;
    if (isSpelling && typeof model_answer === "string" && model_answer.trim()) {
      const norm = (s: unknown) => String(s ?? "").trim().toLowerCase();
      correct = norm(student_response) === norm(model_answer);
    }

    return json({
      correct,
      feedback: sanitizeText(verdict.feedback),
      word_count: verdict.word_count ?? null,
      mistakes: Array.isArray(verdict.mistakes)
        ? verdict.mistakes.map((m) => sanitizeText(m))
        : [],
      model_essay: verdict.model_essay ? sanitizeText(verdict.model_essay) : null,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return json({ error: message }, 500);
  }
});
