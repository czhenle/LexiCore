// Reading — its rung ladder (vocab_preview→mcq_literal→sequence_order→
// mcq_inference(KBAT)→open_response), near-verbatim from generate/index.ts.
// Passage-grounding (context_passage) is skill-agnostic engine logic, not
// specific to Reading, so it isn't duplicated here — Reading's per-session
// passage reuse (see mastery_service.dart / reading_module_screen.dart) just
// passes context_passage like guided comprehension already does.
import type { GenParams, SkillModule } from "./types.ts";

export const readingModule: SkillModule = {
  choiceFormats: new Set(["vocab_preview", "mcq_literal", "sequence_order", "mcq_inference"]),

  formatHint(format) {
    switch (format) {
      case "vocab_preview":
        return "Introduce one key word with its meaning, then ask a simple recognition question about it. Options are 4 answer candidates.";
      case "sequence_order":
        return "The question gives a jumbled set of words or sentences. Options are 4 candidate full orderings — only one is correct, not individual words.";
      case "mcq_inference":
        return "Test inference, reasoning, cause/effect, interpretation, or comparison — still answerable from the passage, but requiring thought beyond direct retrieval (this is the KBAT-equivalent rung). Options are 4 answer candidates.";
      default:
        return "";
    }
  },

  openExtra(p: GenParams) {
    // open_response grounded in a passage is initial_assessment_screen.dart's
    // guided comprehension check, fixed at rung 4 (TRANSFER) — but the base
    // prompt's rung-4 framing ("apply the concept in a new/extended
    // context") on its own pushes the model toward inventing a hypothetical
    // scenario about the student's own life instead of checking whether
    // they understood the passage, which is the actual point of this item.
    // Override that explicitly rather than relying on rung alone to imply it.
    if (p.format === "open_response" && p.context_passage) {
      return ` Despite the "TRANSFER" framing above, this is a GUIDED COMPREHENSION check, not a transfer/hypothetical task: ask ONE open-response question that checks understanding of the passage directly — what happened, why a character did something, or what a key idea/lesson was — answerable in the student's own words FROM the passage's own content. Do NOT ask them to imagine a new scenario about their own life, invent a plan, or apply the idea elsewhere. Stay grounded in what the passage itself says.`;
    }
    return ""; // open_response with no passage needs nothing extra beyond the universal open-item shape.
  },

  requiredKeysExtra() {
    return [];
  },

  validateExtra() {
    return [];
  },
};
