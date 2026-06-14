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

// Clean and normalise the incoming message so minor formatting issues
// (missing punctuation, extra spaces, mixed case) don't confuse the model
function normaliseMessage(raw: string): string {
  let msg = raw.trim();
  // Add a full stop if the message ends without punctuation
  if (msg.length > 0 && !/[.!?]$/.test(msg)) {
    msg = msg + ".";
  }
  return msg;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const body = await req.json();
    const {
      message       = "",
      standard      = 3,
      detected_level = 3,
      weakness      = "Grammar",
      vocab_score   = 0,
      grammar_score = 0,
      reading_score = 0,
      writing_score = 0,
    } = body;

    // Normalise message — adds punctuation if missing so model parses it reliably
    const cleanMessage = normaliseMessage(String(message));

    if (!cleanMessage || cleanMessage === ".") {
      return jsonResponse({ reply: "I didn't catch that! Can you type your question again? 😊" });
    }

    const openai = new OpenAI();

    const systemPrompt = `You are Lexi, a warm and encouraging English tutor for Malaysian primary school students.

      Student profile:
      - School standard: ${standard}
      - Current ability level: ${detected_level}
      - Weakest skill: ${weakness}
      - Skill scores — Vocabulary: ${vocab_score}%, Grammar: ${grammar_score}%, Reading: ${reading_score}%, Writing: ${writing_score}%

      Your personality and behaviour:
      1. Always respond in simple, friendly English suitable for a Standard ${detected_level} student
      2. Understand the INTENT of what the student is saying — even if their sentence is incomplete, has no punctuation, or has grammar mistakes. Focus on what they MEAN, not how perfectly they wrote it.
      3. If the student writes something like "Although it rained I still need go school" — understand they want help with grammar/conjunction usage and respond helpfully
      4. When explaining grammar or vocabulary, always give a clear example sentence at Standard ${detected_level} level
      5. If the student asks about ${weakness}, give extra encouragement and step-by-step help
      6. Keep responses short and friendly — 3 to 5 sentences maximum unless they ask for more detail
      7. End every response with either a helpful follow-up question OR a word of encouragement
      8. Never use complicated vocabulary the student wouldn't know at Standard ${detected_level} level
      9. If the student's message contains a grammar mistake, gently point it out at the END of your response with a small tip — never make them feel bad about it
      10. If you genuinely cannot understand what the student means, ask ONE simple clarifying question like "Can you tell me a little more about what you need help with?"

      Remember: You are patient, kind, and always make the student feel capable and supported.`;

    const response = await openai.chat.completions.create({
      model:      "gpt-4o-mini",
      messages:   [
        { role: "system", content: systemPrompt },
        { role: "user",   content: cleanMessage },
      ],
      temperature: 0.75,
    });

    const reply = response.choices[0]?.message?.content?.trim() ??
                  "Hmm, I had a little trouble with that! Could you try asking me again? 😊";

    return jsonResponse({ reply });

  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, 500);
  }
});