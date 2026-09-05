// Grammar — a near-verbatim extraction of what already lived in generate/
// index.ts, plus one rebalance: rung 4 (transform_or_reorder) moved from
// choice to open, so the ladder isn't 4-of-5 rungs MCQ (worked_example,
// mcq_identify_or_error, gap_fill, transform_or_reorder were ALL choice —
// only rung 5 was ever open-response, and rung progression naturally
// lingers on lower rungs, so students saw mostly MCQ). Now 3-of-5.
import type { GenParams, Item, SkillModule } from "./types.ts";

export const grammarModule: SkillModule = {
  choiceFormats: new Set([
    "mcq_identify_or_error", "worked_example", "gap_fill",
  ]),

  formatHint(format) {
    switch (format) {
      case "worked_example":
        return `This is the GENTLEST rung: the student sees a solved example, then answers a similar question. The example must reach them BEFORE they answer, so put each part in its own field — an example buried in "explanation" is only revealed after they have already guessed, which defeats the entire format:
- "context_text": the worked example itself, fully solved, 1-2 short sentences (e.g. "Mei is my friend. She is kind. The word 'She' is a pronoun because it replaces 'Mei'."). Do NOT put the new question in here.
- "question": ONLY the new question, about a DIFFERENT sentence than the worked example (e.g. "Which word is a pronoun in: 'Ali lost his bag'?"). Do NOT repeat the worked example in here.
- Options are 4 answer candidates for that new question.
- "explanation": why the correct option is right — this is read AFTER answering, so it must not be the only place the example appears.`;
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

  requiredKeysExtra(p: GenParams) {
    // worked_example is only a scaffold if the example actually reaches the
    // student before they answer — so the field carrying it is required.
    return p.format === "worked_example" ? ["context_text"] : [];
  },

  validateExtra(item: Item, p: GenParams) {
    const issues: string[] = [];
    if (p.format === "worked_example") {
      const context = (item.context_text ?? "").toString().trim();
      if (!context) {
        issues.push(
          "worked_example item must put the solved example in context_text (shown BEFORE answering), not only in explanation",
        );
      }
      // Guards the other half of the failure: the example present, but the
      // "question" just restating it rather than asking something new.
      const question = (item.question ?? "").toString().trim();
      if (context && question && question.length > 0 && context === question) {
        issues.push("worked_example item's question must ask something NEW, not repeat context_text");
      }
    }
    return issues;
  },
};
