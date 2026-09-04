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

const MAX_MESSAGE_LENGTH = 3000;
const MAX_HISTORY = 10;

const VALID_TYPES = new Set([
  "word_meaning",
  "grammar_explanation",
  "reading_help",
  "guiding_hint",
  "writing_feedback",
  "writing_ideas",
  "example_generation",
  "practice_question",
  "study_advice",
  "simple_answer",
]);

// Just tidy whitespace — don't change the student's actual words.
function normaliseMessage(raw: string): string {
  return raw.trim().replace(/\s+/g, " ");
}

function modePrompt(mode: string): string {
  switch (mode) {
    case "homework":
      return "MODE — Homework: give hints and guiding questions only. NEVER the final answer.";
    case "practice":
      return "MODE — Practice: ask ONE question, then wait. When the student answers, gently say if it's right and why.";
    case "revision":
      return "MODE — Revision: a short reminder of the idea, then one quick check question.";
    case "teach":
      return "MODE — Teach: explain simply, give ONE example, then ask ONE check question.";
    default:
      return "MODE — Auto: choose the most helpful way to respond based on what the student needs.";
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const body = await req.json();
    const {
      message = "",
      history = [],
      mode = "auto",
      standard = 3,
      weakness = "Grammar",
      vocab_score = 0,
      grammar_score = 0,
      reading_score = 0,
      writing_score = 0,
      topic = "",
      learningObjective = "",
      image = null,
    } = body;

    const cleanMessage = normaliseMessage(String(message));

    if (!cleanMessage && !image) {
      return jsonResponse({
        reply: { type: "simple_answer", text: "I didn't catch that! Type a question or send a photo. 😊" },
      });
    }
    if (cleanMessage.length > MAX_MESSAGE_LENGTH) {
      return jsonResponse({
        reply: { type: "simple_answer", text: "That message is a little too long. Please send a shorter question. 😊" },
      }, 400);
    }

    const openai = new OpenAI({ apiKey: Deno.env.get("OPENAI_API_KEY") });
    const imageDataUrl = image
      ? (String(image).startsWith("data:") ? String(image) : `data:image/jpeg;base64,${image}`)
      : null;

    // Prompt sections (easier to maintain than one giant string).
    const BASE = `You are Lexi, a warm, patient English tutor for Malaysian primary school children.
You are a GUIDE, not an answer machine.`;

    const rules = `HOW TO DECIDE WHAT TO DO:
- If the student wants to LEARN a concept (e.g. "what is a noun?") — explain it simply.
- If the student wants the FINAL ANSWER to homework/an exercise — do NOT give it; give a hint and a guiding question.
- If the student shows THEIR OWN attempt (e.g. "I think it's 'went', is that right?") — give feedback and guide them, don't just replace their answer.
- Prefer ONE guiding question at a time; wait for their reply before the next hint.
- Never write a full essay or draft for them — help them plan instead.`;

    const profile = `STUDENT PROFILE (use to set difficulty — do NOT claim to follow any official syllabus):
- School standard: ${standard}
- Weakest skill: ${weakness}
- Scores — Vocabulary ${vocab_score}/100, Grammar ${grammar_score}/100, Reading ${reading_score}/100, Writing ${writing_score}/100
Match your difficulty to this level and give extra support in ${weakness}.`;

    const lesson = (topic || learningObjective)
      ? `LESSON CONTEXT: topic="${topic}", objective="${learningObjective}". Keep help relevant to this.`
      : "";

    const style = `STYLE:
- Simple words and short sentences a Standard ${standard} child understands.
- British English spelling (colour, centre, favourite, organise).
- Examples familiar to Malaysian children. Be warm; praise effort; never shame mistakes.`;

    const safety = `CHILD SAFETY: You are talking to a child. Never ask for full name, home address, phone number, passwords, school login, exact location, or private family details, and don't encourage sharing them. If the student raises an unsafe or grown-up topic, keep your reply short and kindly suggest they talk to a trusted adult (parent or teacher).`;

    const schema = `Reply with ONE JSON object and NOTHING ELSE. Pick exactly one "type" and fill only its fields:
- word_meaning: {"type","word","pronunciation","meaning","when_to_use","example"}
- grammar_explanation: {"type","topic","text","example","check_question"}
- reading_help: {"type","text","tip","question"}
- guiding_hint: {"type","hint","question"}
- writing_feedback: {"type","did_well","to_improve","next_step"}
- writing_ideas: {"type","text","ideas":["...","..."]}
- example_generation: {"type","text","examples":["...","..."]}
- practice_question: {"type","question","hint"}
- study_advice: {"type","text","tips":["...","..."]}
- simple_answer: {"type","text"}
Keep every field short and simple.`;

    const imagePrompt = imageDataUrl
      ? `The student sent a PHOTO. Work out what it is (worksheet, textbook page, handwritten answer, essay, grammar exercise, reading passage, or multiple-choice question) and add a "detected_task" field with that label. If it is their own writing use writing_feedback; if it is a question/exercise use guiding_hint. Never give the completed answer.`
      : "";

    const instructions = [BASE, rules, profile, lesson, style, safety, modePrompt(mode), schema, imagePrompt]
      .filter(Boolean)
      .join("\n\n");

    // Conversation history (last N turns).
    const recent = Array.isArray(history) ? history.slice(-MAX_HISTORY) : [];
    const historyInput = recent
      .filter((h: any) => h && typeof h.text === "string" && h.text.trim().length > 0)
      .map((h: any) => {
        const isLexi = h.role === "lexi" || h.role === "assistant";
        return {
          role: isLexi ? "assistant" : "user",
          content: [{ type: isLexi ? "output_text" : "input_text", text: String(h.text) }],
        };
      });

    // Current user turn (word "json" satisfies the json_object format rule).
    const userText = (cleanMessage === "" ? "Please look at my photo and help me." : cleanMessage) +
      "\n\n(Reply as JSON.)";
    const userContent = imageDataUrl
      ? [
          { type: "input_text", text: userText },
          { type: "input_image", image_url: imageDataUrl },
        ]
      : [{ type: "input_text", text: userText }];

    const input = [...historyInput, { role: "user", content: userContent }];

    const response = await openai.responses.create({
      model: "gpt-5.6-luna",
      instructions,
      input: input as any,
      reasoning: { effort: "low" },
      text: { format: { type: "json_object" } },
    });

    const raw = (response.output_text as string | undefined)?.trim() ?? "";

    // Validate structure, not just JSON-ness.
    let reply: any;
    try {
      reply = JSON.parse(raw);
    } catch {
      reply = null;
    }
    if (!reply || typeof reply !== "object" || !("type" in reply) || !VALID_TYPES.has(reply.type)) {
      reply = {
        type: "simple_answer",
        text: "I'm not sure how to help with that yet. Can you ask in a different way? 😊",
      };
    }

    return jsonResponse({ reply });
  } catch (error) {
    // Log details server-side; return a safe, generic message to the client.
    console.error("Lexi error:", error);
    return jsonResponse({
      error: "LEXI_ERROR",
      message: "Lexi is having trouble right now. Please try again in a moment. 😊",
    }, 500);
  }
});