// Writing — sentence_complete/sentence_combine (choice), error_correction_rewrite
// (open, replaces the 100%-failing punctuation_fix — see migration
// 20260903000002; still served by the general rung ladder, no longer a
// standalone mode-card), and guided/free composition (open, needs a
// per-Standard word-count target from the shared syllabus config) — guided
// and free are also WritingModuleScreen's 2 mode-cards, format pinned by
// mode rather than derived from rung, same mechanism as Vocabulary's modes.
import type { GenParams, Item, SkillModule } from "./types.ts";

interface WritingSyllabus {
  writingComplexity: string;
  writingMinWords: number;
}

export const writingModule: SkillModule = {
  choiceFormats: new Set(["sentence_complete", "sentence_combine"]),

  formatHint(format) {
    switch (format) {
      case "sentence_combine":
        return "The question gives two short sentences to combine into one. Options are 4 candidate combined sentences — only one is grammatically correct.";
      default:
        return "";
    }
  },

  openExtra(p: GenParams, syllabusRaw: unknown) {
    if (p.format === "error_correction_rewrite") {
      return ` This is an ERROR-CORRECTION item: write a short passage (2-4 sentences) containing a few deliberate vocabulary and/or grammar mistakes appropriate for Standard ${p.standard} (do NOT touch punctuation-only — the mistakes must be real vocabulary/grammar errors, e.g. wrong word choice, wrong tense, wrong plural). The "question" must show this flawed passage and ask the student to rewrite it correctly. "answer" is the fully corrected passage. "explanation" briefly lists which errors were fixed.`;
    }
    if (p.format === "guided_composition") {
      return ` This is a GUIDED WRITING item: give the student an everyday situation grounded in a picture. Pick a DIFFERENT everyday scenario each time — do not default to any single one of these, they're only illustrations of the VARIETY expected: a market, a birthday party, a school sports day, a rainy afternoon, helping a neighbour, cooking with a grandparent, a visit to the clinic, a trip to the library, planting a garden, a school trip. Provide:
- "image_keyword": a single simple concrete scene DALL-E can illustrate clearly, matching the situation (e.g. "a birthday party with balloons and a cake").
- "question": one short OPENING SENTENCE the student continues from (e.g. "Today, you are helping to plant a garden at school."), followed by an instruction to continue the story in their own words.
- "hints": an array of 3-4 short phrases naming things they could mention, specific to whichever scenario was picked — guidance, not a script.
Do NOT write the rest of the story yourself — "answer" is a short model continuation (2-3 sentences) showing what a good response looks like, for the teacher/grader's reference only.`;
    }
    if (p.format === "free_composition") {
      return ` This is a FREE WRITING item: give the student a topic/title for a short essay and nothing more scaffolded than that. Pick a DIFFERENT topic each time — do not default to any single one of these, they're only illustrations of the VARIETY expected: a hobby, a favourite place, an animal, a festival or celebration, a person they admire, a memorable day, a skill they want to learn, their favourite food, a place they'd like to visit. Provide:
- "question": one clear topic or title (e.g. "Write about your favourite hobby.").
- "hints": an array of 2-3 loose categories they could choose to write about, specific to whichever topic was picked — options, not requirements; the student may write about anything related to the topic.
"answer" is a short model outline of what a good response could cover, for the teacher/grader's reference only.`;
    }
    // Both composition formats need an actual word-count target and
    // complexity guidance, or they default to whatever length the model feels
    // like.
    const syllabus = syllabusRaw as WritingSyllabus;
    if (syllabus.writingMinWords > 0) {
      return `\nWriting complexity for Standard ${p.standard}: ${syllabus.writingComplexity}\nThis is a written composition response — require at least ${syllabus.writingMinWords} words.`;
    }
    return "";
  },

  requiredKeysExtra(p: GenParams) {
    switch (p.format) {
      case "guided_composition":
        return ["image_keyword", "hints"];
      case "free_composition":
        return ["hints"];
      default:
        return [];
    }
  },

  validateExtra(item: Item, p: GenParams) {
    const issues: string[] = [];
    if (p.format === "guided_composition" && !item.image_keyword) {
      issues.push("guided_composition item must include image_keyword");
    }
    if ((p.format === "guided_composition" || p.format === "free_composition") &&
      (!item.hints || item.hints.length < 2)) {
      issues.push(`${p.format} item must include hints with at least 2 entries`);
    }
    return issues;
  },

  async postProcess(item: Item, p: GenParams, openai) {
    if (p.format !== "guided_composition" || !item.image_keyword) return;
    // One picture per served item, wrapped so an image failure never fails
    // the whole item — the client already handles a null image_b64 gracefully.
    try {
      const img = await openai.images.generate({
        model: "gpt-image-2-2026-04-21",
        prompt: `Simple, cute, kid-friendly illustration of ${item.image_keyword}. Flat vector art style, clean white background, no text, no labels.`,
        n: 1,
        size: "1024x1024",
        quality: "low",
      });
      item.image_b64 = img.data?.[0]?.b64_json ?? null;
    } catch (e) {
      console.error("image gen failed:", e);
      item.image_b64 = null;
    }
  },
};
