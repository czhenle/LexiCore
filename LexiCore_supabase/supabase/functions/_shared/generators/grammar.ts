// Grammar — a near-verbatim extraction of what already lived in generate/
// index.ts, plus one rebalance: rung 4 (transform_or_reorder) moved from
// choice to open, so the ladder isn't 4-of-5 rungs MCQ (worked_example,
// mcq_identify_or_error, gap_fill, transform_or_reorder were ALL choice —
// only rung 5 was ever open-response, and rung progression naturally
// lingers on lower rungs, so students saw mostly MCQ). Now 3-of-5.
import type { GenParams, SkillModule } from "./types.ts";

export const grammarModule: SkillModule = {
  choiceFormats: new Set([
    "mcq_identify_or_error", "worked_example", "gap_fill",
  ]),

  formatHint(format) {
    switch (format) {
      case "worked_example":
        return "Show a worked example first, then ask a simple recognition question about it. Options are 4 answer candidates.";
      case "gap_fill":
        return "The question is a sentence or short passage with a blank. Options are 4 candidate words/phrases to fill the blank.";
      default:
        return "";
    }
  },

  openExtra(p: GenParams) {
    if (p.format === "transform_or_reorder") {
      return ` This is a TRANSFORM/REORDER item: give the student ONE sentence to change — either transform it (e.g. change tense, change to a question/negative, change voice) or reorder a jumbled set of words/phrases into a correct sentence. State clearly which of the two is being asked. "answer" is the student's own correctly transformed/reordered sentence — there is no fixed set of options to pick from.`;
    }
    return ""; // Grammar's other open format (open_sentence) needs nothing extra.
  },

  requiredKeysExtra() {
    return [];
  },

  validateExtra() {
    return [];
  },
};
