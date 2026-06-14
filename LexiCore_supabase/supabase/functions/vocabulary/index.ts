import OpenAI from "npm:openai";
import { ChatOpenAI } from "npm:@langchain/openai";
import { ChatPromptTemplate } from "npm:@langchain/core/prompts";
import { z } from "npm:zod";

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

// ── Schema ───────────────────────────────────────────────────────────────────
const baseSchema = z.object({
  questions: z.array(z.object({
    question:       z.string(),
    options:        z.object({ A: z.string(), B: z.string(), C: z.string(), D: z.string() }),
    correct_answer: z.enum(["A", "B", "C", "D"]),
    explanation:    z.string(),
  })),
});

const imageSchema = z.object({
  questions: z.array(z.object({
    question:       z.string(),
    options:        z.object({ A: z.string(), B: z.string(), C: z.string(), D: z.string() }),
    correct_answer: z.enum(["A", "B", "C", "D"]),
    explanation:    z.string(),
    image_keyword:  z.string().describe("A single simple concrete noun for DALL-E, e.g. 'elephant', 'bicycle', 'apple'"),
  })),
});

const contextSchema = z.object({
  questions: z.array(z.object({
    context_text:   z.string().describe("A sentence with ___ as the blank"),
    question:       z.string(),
    options:        z.object({ A: z.string(), B: z.string(), C: z.string(), D: z.string() }),
    correct_answer: z.enum(["A", "B", "C", "D"]),
    explanation:    z.string(),
  })),
});

// ── Random word pool — varied across many everyday topics ────────────────────
// Instead of locking to one topic, we pick from a broad pool so each session
// feels fresh and covers a wide range of vocabulary a student should know.
const wordPoolByLevel: Record<number, string> = {
  1: "simple everyday words like body parts, colours, numbers, common animals, food items, and household objects",
  2: "familiar words like clothing, weather, fruits and vegetables, school supplies, and simple action words",
  3: "intermediate words like community places, transport, nature, feelings, and common verbs",
  4: "varied vocabulary including adjectives, compound words, hobbies, health, and environment",
  5: "broader vocabulary including occupations, technology, science, culture, and descriptive language",
  6: "advanced vocabulary including abstract nouns, idioms in context, formal and informal registers, and complex adjectives",
};

// ─────────────────────────────────────────────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { standard = 3, mode = "meaning" } = await req.json();
    // topic is intentionally ignored — we use the random word pool instead

    const level    = Math.min(Math.max(Number(standard), 1), 6);
    const wordPool = wordPoolByLevel[level] ?? wordPoolByLevel[3];

    const llm = new ChatOpenAI({ model: "gpt-4o-mini", temperature: 0.9 });

    // ── IMAGE MODE ───────────────────────────────────────────────────────────
    if (mode === "image") {
      const structuredLlm = llm.withStructuredOutput(imageSchema);
      const prompt = ChatPromptTemplate.fromMessages([
        ["system", `You are a KSSR English Teacher for Standard ${level}.`],
        ["human", `Create 5 vocabulary multiple-choice questions. 
          Each question shows a different word from this broad pool: ${wordPool}.
          Pick 5 DIFFERENT words — do NOT use the same topic twice.
          Each question asks "What is this?" and shows an image.
          The image_keyword must be a single concrete noun that DALL-E can illustrate clearly (e.g. "umbrella", "bicycle", "mango").
          Example question: "What is this?" with an image of a bicycle, options: A) car B) bicycle C) airplane D) boat
          Make all 4 options plausible but only one correct.`],
      ]);
      const result = await prompt.pipe(structuredLlm).invoke({});

      const openai = new OpenAI();
      const withImages = await Promise.all(
        result.questions.map(async (q) => {
          try {
            const img = await openai.images.generate({
              model:  "dall-e-2",
              prompt: `Simple, cute, kid-friendly illustration of a ${q.image_keyword}. Flat vector art style, clean white background, no text, no labels.`,
              n:      1,
              size:   "256x256",
            });
            return { ...q, image_url: img.data?.[0]?.url ?? null };
          } catch {
            return { ...q, image_url: null };
          }
        })
      );
      return jsonResponse({ questions: withImages });
    }

    // ── MEANING MODE ─────────────────────────────────────────────────────────
    if (mode === "meaning") {
      const structuredLlm = llm.withStructuredOutput(baseSchema);
      const prompt = ChatPromptTemplate.fromMessages([
        ["system", `You are a KSSR English Teacher for Standard ${level}.`],
        ["human", `Create 5 vocabulary questions. 
          Pick 5 DIFFERENT words from this broad pool: ${wordPool}.
          Do NOT restrict to one topic — mix different categories freely.
          Each question gives a definition and asks which word matches.
          Example: "Which word means moving very fast?" A) slow B) quick C) heavy D) quiet
          Make sure the words chosen are varied and appropriate for Standard ${level} students.`],
      ]);
      const result = await prompt.pipe(structuredLlm).invoke({});
      return jsonResponse(result);
    }

    // ── CONTEXT MODE ─────────────────────────────────────────────────────────
    if (mode === "context") {
      const structuredLlm = llm.withStructuredOutput(contextSchema);
      const prompt = ChatPromptTemplate.fromMessages([
        ["system", `You are an experienced KSSR English Teacher designing vocabulary-in-context exercises for Standard ${level} students.
          Your goal is to help students:
          1. Distinguish between commonly confused or similar-meaning words (e.g. "fast" vs "quick", "big" vs "large", "happy" vs "glad")
          2. Understand how word choice changes meaning depending on situation or context
          3. Build accuracy in real-life vocabulary usage appropriate for their level`],
        ["human", `Create 5 vocabulary-in-context fill-in-the-blank questions for Standard ${level} students.

          WORD SELECTION:
          - Pick 5 DIFFERENT words from this pool: ${wordPool}
          - Prioritise words that have common near-synonyms or are frequently misused at Standard ${level} level
          - Vary the word categories — do NOT pick multiple words from the same topic

          SENTENCE DESIGN RULES:
          - Each context_text must be a natural, realistic sentence with ___ as the blank
          - The sentence must provide enough context clues so that only ONE word is clearly correct
          - Sentences must reflect real-life scenarios a Malaysian Standard ${level} student would recognise (school, home, market, playground, etc.)
          - Sentence length and vocabulary must be appropriate for Standard ${level} (age ${level + 6})

          DISTRACTOR DESIGN RULES:
          - At least 2 of the 4 options must be plausible near-synonyms or related words that students commonly confuse
          - Distractors must be from the same word class as the correct answer (e.g. all adjectives, all verbs)
          - Avoid obviously wrong options that a student could eliminate without reading the sentence

          EXPLANATION:
          - For each question, briefly explain WHY the correct word fits and why the near-synonym distractors do NOT fit in that specific context

          Example of a well-designed question:
          context_text: "The athlete ran ___ across the finish line to win the race."
          question: "Which word best completes the sentence?"
          options: A) quick  B) fast  C) hurried  D) rushed
          correct_answer: B
          explanation: "'Fast' describes sustained high speed, which fits an athlete's consistent running pace. 'Quick' implies a brief burst of speed, 'hurried' suggests nervousness, and 'rushed' implies carelessness — none fit a competitive race context."`],
      ]);
      const result = await prompt.pipe(structuredLlm).invoke({});
      return jsonResponse(result);
    }

    return jsonResponse({ error: "Invalid mode. Use: image | meaning | context" }, 400);

  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, 500);
  }
});