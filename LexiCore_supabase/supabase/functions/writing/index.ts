import { ChatOpenAI } from "npm:@langchain/openai";
import { ChatPromptTemplate } from "npm:@langchain/core/prompts";
import { z } from "npm:zod";
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

// Base schema (completion/ordering/correction, and low-Standard "guided" composition)
const writingSchema = z.object({
  questions: z.array(z.object({
    context_text:   z.string().describe("The sentence/paragraph context. For completion: sentence with ___. For ordering: jumbled words separated by |. For correction: the sentence with an error. For composition: the writing prompt."),
    question:       z.string().describe("The specific instruction for this question"),
    options:        z.object({ A: z.string(), B: z.string(), C: z.string(), D: z.string() }),
    correct_answer: z.enum(["A", "B", "C", "D"]),
    explanation:    z.string().describe("Explanation of the correct answer and the writing rule"),
  })),
});

// Open schema: a genuine free-text paragraph task, used for "composition" at
// Standard >= 3 per LexiCore_Syllabus_Specification.md sections 9-13 — a
// real writing prompt with a minimum word count, not a 4-option MCQ.
// Validation/AI-grading of the student's actual text is out of scope this
// phase; the client reveals model_answer + checklist and lets the student
// self-assess, the same pattern already used by the adaptive practice loop.
const openSchema = z.object({
  prompt:        z.string().describe("The writing task itself, e.g. 'Write at least N words about...'"),
  min_words:     z.number().describe("Minimum word count expected at this Standard"),
  model_answer:  z.string().describe("A model response meeting the prompt, at the target Standard's complexity"),
  checklist:     z.array(z.string()).describe("3-5 short self-check items, e.g. 'Used at least one descriptive adjective'"),
  explanation:   z.string().describe("Brief note on what makes the model answer work"),
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const {
      standard      = 3,
      topic         = "Everyday Tasks",
      exercise_type = "completion",
    } = await req.json();

    const level    = Math.min(Math.max(Number(standard), 1), 6);
    const syllabus = standardSyllabus(level);
    const llm      = new ChatOpenAI({ model: "gpt-5.6-luna"});

    // Per LexiCore_Syllabus_Specification.md sections 9-13: composition
    // moves from guided/MCQ-style at Standard < 3 to genuine independent
    // paragraph writing with a minimum word count at Standard >= 3.
    if (exercise_type === "composition" && level >= 3) {
      const openLlm = llm.withStructuredOutput(openSchema);
      const prompt = ChatPromptTemplate.fromMessages([
        ["system", `You are an English writing teacher for Standard ${level} (age ${level + 6}).
          Vocabulary/grammar must stay within: ${syllabus.allowedGrammar}
          Writing complexity for this Standard: ${syllabus.writingComplexity}`],
        ["human", `Create ONE writing prompt about "${topic}" for a Standard ${level} student.
          The prompt must ask for at least ${syllabus.writingMinWords} words.
          Provide a model_answer that meets the prompt at this Standard's complexity — not simpler, not more advanced.
          Provide a short self-check checklist (3-5 items) the student can use to review their own writing.`],
      ]);
      const result = await prompt.pipe(openLlm).invoke({});
      return jsonResponse({
        questions: [{
          context_text: result.prompt,
          question: `Write your response below (at least ${result.min_words} words).`,
          is_open: true,
          min_words: result.min_words,
          model_answer: result.model_answer,
          checklist: result.checklist,
          explanation: result.explanation,
        }],
      });
    }

    const structuredLlm = llm.withStructuredOutput(writingSchema);

    // ── Prompts per exercise type ────────────────────────────────────────────
    const prompts: Record<string, string> = {
      completion: `Create 5 sentence completion questions about "${topic}".
        Each context_text is a sentence with ___ as the blank.
        The question asks: "Choose the best word to complete the sentence."
        Options should be 4 different words. Only one makes grammatical and contextual sense.
        Example: context_text = "She ___ to school every morning.", question = "Which word best completes the sentence?", options A=walks B=eating C=jumped D=sleep`,

              ordering: `Create 5 sentence ordering questions about "${topic}".
        Each context_text contains jumbled words separated by " | " (e.g. "went | to | He | school | yesterday").
        The question asks: "Arrange these words into a correct sentence."
        Options should be 4 different orderings. Only one is grammatically correct.`,

              correction: `Create 5 error correction questions about "${topic}".
        Each context_text is a sentence with ONE grammar or spelling error.
        The question asks: "Which word in the sentence is incorrect? Choose the correction."
        Options should be 4 possible corrections. Only one is correct.
        Example: context_text = "She don't like apples.", question = "Which word should be corrected?"
        Options: A=doesn't B=do not C=didn't D=not`,

              composition: `Create 5 guided composition questions about "${topic}".
        Each context_text is a short writing prompt (2-3 sentences describing a situation). 
        The question asks students to choose the best sentence to continue or complete the paragraph.
        Options should be 4 different sentences. Only one is stylistically and grammatically best.
        Example: context_text = "Ahmad went to the market with his mother. They wanted to buy vegetables.", 
        question = "Which sentence best continues this paragraph?"
        Options: A=They buyed carrots and tomatoes. B=They bought fresh carrots and tomatoes. C=They has carrots. D=Market was open.`,
    };

    const systemPrompt = `You are an English writing teacher for Standard ${level}.
      Vocabulary and grammar must stay within: ${syllabus.allowedGrammar}
      Sentence complexity should be appropriate for Standard ${level} students (age ${level + 6}).
      All exercises should be educational, relevant to Malaysian primary school students, and focused on improving writing skills.`;

    const userPrompt = prompts[exercise_type] ?? prompts["completion"];

    const prompt = ChatPromptTemplate.fromMessages([
      ["system", systemPrompt],
      ["human",  userPrompt],
    ]);

    const result = await prompt.pipe(structuredLlm).invoke({});
    return jsonResponse(result);

  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, 500);
  }
});