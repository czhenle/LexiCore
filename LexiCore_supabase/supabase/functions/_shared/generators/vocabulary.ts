// Vocabulary — the one skill with two distinct format families:
//
// 1. The EXISTING topic-based adaptive ladder (meaning_match, mcq_word_meaning,
//    cloze_sentence_wordbank, cloze_paragraph_open, open_sentence) — already
//    live, used by Today's Task/the weekly assessment against real per-topic
//    sub_skills (e.g. vocab.family). Untouched by this module beyond
//    open_sentence's existing target_word/hint/image_keyword extras.
//
// 2. NEW mode-based formats (vocab_image_mcq/open, vocab_meaning_mcq/open,
//    vocab_context_mcq, vocab_synonyms_mcq, vocab_spelling_open) — one per
//    mode-card in VocabularyModuleScreen, against 5 new non-topic sub_skills
//    (vocab.mode_*). mcq-vs-open for image/meaning is chosen by the CLIENT
//    (which literal format string it requests), not by the model at
//    request time — this is the one skill where format isn't purely
//    rung-derived, since "which mode the student tapped" matters as much as
//    difficulty. Ports vocabulary/index.ts's per-mode prompts, now scoped to
//    ONE item per call instead of a 5-question batch.
import type { GenParams, Item, SkillModule } from "./types.ts";

const IMAGE_FORMATS = new Set(["vocab_image_mcq", "vocab_image_open", "vocab_spelling_open"]);

export const vocabularyModule: SkillModule = {
  choiceFormats: new Set([
    "meaning_match", "mcq_word_meaning", "cloze_sentence_wordbank",
    "vocab_image_mcq", "vocab_meaning_mcq", "vocab_context_mcq", "vocab_synonyms_mcq",
  ]),

  formatHint(format) {
    switch (format) {
      case "vocab_image_mcq":
        return `The question asks "What is this?" about an image. Also provide "image_keyword": a single simple concrete noun DALL-E can illustrate clearly — pick a DIFFERENT everyday object/animal/food/place each time, spanning varied categories (e.g. animals: elephant, frog, sparrow; food: mango, bread, noodles; objects: umbrella, bicycle, kite; nature: mountain, waterfall, cactus; places: lighthouse, market, playground) — do not default to the same word or category every time. Options are 4 plausible words; only one correct.`;
      case "vocab_meaning_mcq":
        return `The question gives a definition/clue (e.g. "Which word means moving very fast?") and asks which word matches. Options are 4 plausible words; only one correct.`;
      case "cloze_sentence_wordbank":
        return `This is a word-bank cloze item, shown to the student as 3 SEPARATE parts — a short instruction, a row of word-bank chips, then the sentence — so keep each part in ITS OWN field, never combined:
- "question": ONLY a short instruction, e.g. "Choose the word from the box that completes the sentence." Do NOT put the sentence or the word list in here.
- "context_text": ONLY the sentence itself, with ___ as the blank. Do NOT repeat the instruction or the word list in here.
- "word_bank": an array of the same 4 words as the options, in a sensible reading order (not necessarily A-D order).
Options A-D are still the same 4 words, for how the student answers — word_bank is purely how those same words are DISPLAYED to the student before they pick.`;
      case "vocab_context_mcq":
        return `This is a fill-in-the-blank item: provide "context_text" — a natural sentence with ___ as the blank. The sentence MUST contain ONE concrete, specific disambiguating detail — a number, a named consequence, a comparison, or a specific result/action — that a careful reader can point to as proof only ONE word fits. Vague mood or tone alone ("it was a ___ day") is NOT enough disambiguation. At least 2 of the 4 options must be plausible near-synonyms students commonly confuse (e.g. "fast" vs "quick"), all the same word class — but that SAME concrete detail must clearly rule each of them out, not just make them "sound less natural". Also provide "explanation_breakdown": an array of EXACTLY 4 {option, label, note} entries — one per option, its own word as "label" and a short clause naming the SPECIFIC detail that confirms or rules it out as "note". Do NOT write one paragraph covering all four instead.`;
      case "vocab_synonyms_mcq":
        return `Either "Which word means the SAME as ___?" (synonym) or "Which word means the OPPOSITE of ___?" (antonym). All 4 options plausible and the same part of speech, but pick distractors from a clearly DIFFERENT shade of meaning, intensity, or formality than the correct answer (e.g. for correct="happy", prefer a distractor like "excited" or "calm" — a different feeling — over "content" or "glad", which are too close to "happy" itself to have one clearly best answer). There must be exactly one option a fair-minded English teacher would mark correct, not several defensible ones. "question" is ONLY that one question sentence — do NOT prefix it with "Word bank: ..." or list the 4 options in prose; the options are already shown to the student separately. Also provide "explanation_breakdown": an array of EXACTLY 4 {option, label, note} entries — one per option. Do NOT write one paragraph covering all four instead.`;
      default:
        return "";
    }
  },

  openExtra(p: GenParams) {
    switch (p.format) {
      case "open_sentence":
        return ` This is a VOCABULARY item, so anchor it to exactly ONE concrete target word the student's sentence must use — pick a word that fits "${p.sub_skill_name}". Also provide:
- "target_word": that one word (lowercase).
- "hint": a short child-friendly clue describing the word WITHOUT saying it or any part of it (e.g. for "sister": "a person older than you who is a girl").
- "image_keyword": the same word (or a close, simple concrete synonym), phrased as a single noun a picture can clearly show DALL-E can illustrate.
The question itself should ask the student to use the target word in a sentence (they'll see the hint and a picture, not the word itself).`;
      case "vocab_image_open":
        return ` Show an image of one word and ask the student to type the word themselves (e.g. "Type the name of what you see."). "answer" is that word (lowercase). Provide "image_keyword": a single concrete noun DALL-E can illustrate clearly — pick a DIFFERENT everyday object/animal/food/place each time, spanning varied categories, not the same word or category every time.`;
      case "vocab_meaning_open":
        return ` Give a definition/clue and ask the student to type the matching word themselves. "answer" is that word (lowercase) — pick a DIFFERENT word each time, not the same one repeatedly. No image involved.`;
      case "vocab_spelling_open":
        return ` This is a SPELLING item: "question" should ask "How do you spell it?", "hint" gives a short child-friendly definition/clue that does NOT reveal any letters of the word or an obvious rhyme, "answer" is the target word (lowercase, this is what the student's typed spelling is checked against, pick a DIFFERENT word each time rather than defaulting to the same one), and "image_keyword" is a single concrete noun DALL-E can illustrate matching the word.`;
      default:
        return "";
    }
  },

  requiredKeysExtra(p: GenParams) {
    switch (p.format) {
      case "open_sentence":
        return ["target_word", "hint", "image_keyword"];
      case "vocab_image_mcq":
        return ["image_keyword"];
      case "vocab_image_open":
        return ["image_keyword"];
      case "vocab_spelling_open":
        return ["hint", "image_keyword"];
      case "cloze_sentence_wordbank":
        return ["context_text", "word_bank"];
      case "vocab_context_mcq":
        return ["context_text", "explanation_breakdown"];
      case "vocab_synonyms_mcq":
        return ["explanation_breakdown"];
      default:
        return [];
    }
  },

  validateExtra(item: Item, p: GenParams) {
    const issues: string[] = [];
    if (p.format === "open_sentence") {
      if (!item.target_word) issues.push("open_sentence item must include target_word");
      if (!item.hint) issues.push("open_sentence item must include hint");
      if (!item.image_keyword) issues.push("open_sentence item must include image_keyword");
    }
    if ((p.format === "vocab_image_mcq" || p.format === "vocab_image_open") && !item.image_keyword) {
      issues.push(`${p.format} item must include image_keyword`);
    }
    if (p.format === "vocab_spelling_open") {
      if (!item.hint) issues.push("vocab_spelling_open item must include hint");
      if (!item.image_keyword) issues.push("vocab_spelling_open item must include image_keyword");
    }
    if (p.format === "vocab_context_mcq" && !item.context_text) {
      issues.push("vocab_context_mcq item must include context_text");
    }
    if (p.format === "cloze_sentence_wordbank") {
      if (!item.context_text) issues.push("cloze_sentence_wordbank item must include context_text");
      if (!item.word_bank || item.word_bank.length !== 4) {
        issues.push("cloze_sentence_wordbank item must include word_bank with exactly 4 entries");
      }
      if (item.question && item.question.length > 80) {
        issues.push("cloze_sentence_wordbank item's question must be a short instruction only, not the sentence or word list");
      }
    }
    if (p.format === "vocab_context_mcq" || p.format === "vocab_synonyms_mcq") {
      if (!item.explanation_breakdown || item.explanation_breakdown.length !== 4) {
        issues.push(`${p.format} item must include explanation_breakdown with exactly 4 entries`);
      }
    }
    return issues;
  },

  async postProcess(item: Item, p: GenParams, openai) {
    if (!IMAGE_FORMATS.has(p.format) && p.format !== "open_sentence") return;
    if (!item.image_keyword) return;
    // One picture per served item, wrapped so an image failure never fails
    // the whole item — the client already handles a null image_b64 gracefully.
    try {
      const img = await openai.images.generate({
        model: "gpt-image-2-2026-04-21",
        prompt: `Simple, cute, kid-friendly illustration of a ${item.image_keyword}. Flat vector art style, clean white background, no text, no labels.`,
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
