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

// Base schema (all exercise types)
const writingSchema = z.object({
  questions: z.array(z.object({
    context_text:   z.string().describe("The sentence/paragraph context. For completion: sentence with ___. For ordering: jumbled words separated by |. For correction: the sentence with an error. For composition: the writing prompt."),
    question:       z.string().describe("The specific instruction for this question"),
    options:        z.object({ A: z.string(), B: z.string(), C: z.string(), D: z.string() }),
    correct_answer: z.enum(["A", "B", "C", "D"]),
    explanation:    z.string().describe("Explanation of the correct answer and the writing rule"),
  })),
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const {
      standard      = 3,
      topic         = "Everyday Tasks",
      exercise_type = "completion",
    } = await req.json();

    const llm           = new ChatOpenAI({ model: "gpt-4o-mini", temperature: 0.7 });
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

    const systemPrompt = `You are a KSSR English Writing Teacher for Standard ${standard}.
      Vocabulary and sentence complexity should be appropriate for Standard ${standard} students (age ${standard + 6}).
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