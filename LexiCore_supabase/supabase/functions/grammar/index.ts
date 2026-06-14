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

const grammarSchema = z.object({
  questions: z.array(z.object({
    question:       z.string(),
    options:        z.object({ A: z.string(), B: z.string(), C: z.string(), D: z.string() }),
    correct_answer: z.enum(["A", "B", "C", "D"]),
    explanation:    z.string().describe("Clear grammar rule explanation suitable for the student level"),
  })),
});

// ── Difficulty profile per level ─────────────────────────────────────────────
const levelProfiles: Record<number, {
  description: string;
  sentenceLength: string;
  questionTypes: string;
  distractorHardness: string;
}> = {
  1: {
    description:        "very simple, 3-5 word sentences with basic nouns and verbs only",
    sentenceLength:     "very short (3–5 words)",
    questionTypes:      "only fill-in-the-blank with obvious choices",
    distractorHardness: "clearly wrong distractors (e.g. a noun vs a verb — obviously different)",
  },
  2: {
    description:        "simple sentences with common verbs, basic articles, and singular/plural",
    sentenceLength:     "short (5–8 words)",
    questionTypes:      "fill-in-the-blank and choose the correct word",
    distractorHardness: "somewhat obvious distractors but with 1 tricky option",
  },
  3: {
    description:        "compound sentences using 'and', 'but', 'or'; present and past tense; basic prepositions",
    sentenceLength:     "medium (8–12 words)",
    questionTypes:      "fill-in-blank, spot the error, choose correct sentence",
    distractorHardness: "plausible distractors that test tense and subject-verb agreement",
  },
  4: {
    description:        "complex sentences with subordinate clauses, adjectives, adverbs, and modal verbs",
    sentenceLength:     "medium-long (10–15 words)",
    questionTypes:      "spot the error, rewrite the sentence, identify the correct form",
    distractorHardness: "close distractors that differ only in tense, modal choice, or word order",
  },
  5: {
    description:        "complex grammar including passive voice, reported speech, conditional sentences (type 1 and 2)",
    sentenceLength:     "long (14–18 words)",
    questionTypes:      "error identification in longer sentences, transformation questions, choose best paraphrase",
    distractorHardness: "very close distractors testing subtle differences (e.g. 'has gone' vs 'had gone' vs 'went')",
  },
  6: {
    description:        "advanced grammar including all conditionals, subjunctive mood, complex passive, and formal register",
    sentenceLength:     "long and complex (16–22 words)",
    questionTypes:      "error correction in formal writing, sentence transformation, register and style questions",
    distractorHardness: "highly plausible distractors that require deep grammar knowledge to distinguish",
  },
};

// ─────────────────────────────────────────────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const {
      standard            = 3,
      topic               = "Simple Sentences",
      questions_per_topic = 3,
    } = await req.json();

    const level   = Math.min(Math.max(Number(standard), 1), 6);
    const profile = levelProfiles[level] ?? levelProfiles[3];

    const llm           = new ChatOpenAI({ model: "gpt-4o-mini", temperature: 0.7 });
    const structuredLlm = llm.withStructuredOutput(grammarSchema);

    const prompt = ChatPromptTemplate.fromMessages([
      ["system", `You are a KSSR English Teacher creating grammar questions for Standard ${level} students.

        DIFFICULTY LEVEL: Standard ${level} out of 6
        Sentence complexity: ${profile.description}
        Sentence length: ${profile.sentenceLength}
        Question format variety: ${profile.questionTypes}
        Distractor difficulty: ${profile.distractorHardness}

        IMPORTANT RULES:
        1. Questions MUST match Standard ${level} difficulty exactly — not easier, not harder
        2. Sentences used in questions must feel natural and age-appropriate for a Standard ${level} student
        3. Grammar rule tested: "${topic}"
        4. All 4 options must be grammatically distinct — no two options should mean the same thing
        5. Explanation must state the grammar rule clearly in simple language a Standard ${level} student understands
        6. Generate EXACTLY ${questions_per_topic} questions with varied formats`],
      ["human", `Generate ${questions_per_topic} Standard ${level} grammar questions about: ${topic}`],
    ]);

    const result = await prompt.pipe(structuredLlm).invoke({});
    return jsonResponse(result);

  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, 500);
  }
});