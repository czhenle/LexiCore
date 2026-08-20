export interface SyllabusContext {
  standard: number;
  year: number;
  cefr: string;
  vocabLevel: string;
  allowedGrammar: string; // cumulative grammar summary up to this Standard
  readingComplexity: string;
  writingComplexity: string;
  writingMinWords: number; // 0 = not a word-count task (guided/simple)
}

const CEFR: Record<number, string> = {
  1: "Pre-A1 /A1 Low",
  2: "A1 Low/A1 Mid",
  3: "A1 Mid/A1 High",
  4: "A1 High",
  5: "A2",
  6: "A2",
};

const VOCAB: Record<number, string> = {
  1:
    "Very simple everyday vocabulary appropriate to Pre-A1/A1 Low. " +
    "Prefer concrete, familiar words and highly familiar child-oriented contexts. " +
    "Emphasize recognition and identification.",

  2:
    "Simple familiar vocabulary appropriate to A1 Low/A1 Mid. " +
    "Use familiar everyday contexts and concrete words. " +
    "Continue recognition while beginning to strengthen understanding and use.",

  3:
    "Broader vocabulary appropriate to A1 Mid/A1 High. " +
    "Increase vocabulary range and begin emphasizing meaning in context, " +
    "word choice, and practical usage.",

  4:
    "A1 High vocabulary with greater variety. " +
    "Use more descriptive language and require more precise word selection " +
    "while remaining appropriate for primary-school learners.",

  5:
    "A2-level vocabulary with a broader range of everyday and academic contexts. " +
    "Encourage contextual understanding, more precise vocabulary use, and " +
    "greater independence.",

  6:
    "A2-level vocabulary with greater range and flexibility. " +
    "Allow more abstract and contextual vocabulary where appropriate, " +
    "including idioms and proverbs when they are part of the syllabus.",
};

const GRAMMAR: Record<number, string> = {
  1:
    "Common nouns (people, animals, places, things); proper nouns " +
    "(people, animals, places, days, months); singular/plural nouns using " +
    "s/es; basic countable/uncountable noun grouping; articles a/an; " +
    "demonstratives this/that/these/those; subject pronouns I/he/she/they/" +
    "we/you/it; possessive adjectives my/your/his/her/its/our/their; " +
    "possessive nouns using 's; subject-verb agreement am/is/are; " +
    "basic simple present; basic simple past including was/were and " +
    "regular d/ed/ied forms; positive and negative statements using " +
    "no/not; WH-questions what/who/where; basic adjectives; basic " +
    "prepositions under/in/on/at/near; simple subject-predicate sentences; " +
    "conjunctions and/or; full stop, comma, question mark and exclamation mark.",

  2:
    "Everything from Standard 1, plus: the; object pronouns me/us/you/them/" +
    "him/her/it; possessive pronouns mine/ours/yours/theirs/his/hers; " +
    "was/were; present continuous am/is/are + verb-ing; WH-questions " +
    "when/which; adjectives of size, shape, colour and quality; expanded " +
    "prepositions of position and direction; conjunctions and/or/but/because.",

  3:
    "Everything from Standard 2, plus: plural noun forms s/es/ies/ves; " +
    "countable/uncountable quantifiers including a few, several, many, " +
    "some, any, a lot of, a little and much; reflexive pronouns; simple " +
    "future and going to using shall/will/going to; negative contractions " +
    "including isn't, aren't, wasn't, weren't, doesn't, don't and didn't; " +
    "WH-questions why/whose/how; adjectives ending in -ful, -less and -y; " +
    "prepositions of time at/on/in/before/after/since; conjunction so; " +
    "synonyms and antonyms.",

  4:
    "Everything from Standard 3, plus: additional plural noun form en; " +
    "expanded countable/uncountable quantifiers; comparative and " +
    "superlative adjectives; adverbs of manner, frequency and time; " +
    "WH-question whom; imperatives; more advanced conjunctions including " +
    "or/whether, therefore, although, if/unless and while/when; modals " +
    "can/could, shall/should, may/might, must/has to/have to.",

  5:
    "Everything from Standard 4, plus: adverbs of place; idioms; proverbs.",

  6:
    "Everything from Standard 5, plus: comparison of adverbs using " +
    "positive, comparative and superlative forms; prepositions of " +
    "manner/instrument including by and with.",
};

const READING_COMPLEXITY: Record<number, string> = {
  1:
    "Very short sentences with concrete and highly familiar topics. " +
    "Use simple sentence structures and direct information retrieval. " +
    "Avoid complex subordinate clauses, advanced vocabulary and idioms.",

  2:
    "Short passages slightly longer than Standard 1. " +
    "Use familiar school, family, hobby, animal and everyday contexts. " +
    "Use simple present, simple past and present continuous where appropriate.",

  3:
    "Short narratives, simple explanations and short informational texts. " +
    "Introduce basic sequencing, cause-and-effect relationships, comparisons " +
    "and simple inference while keeping language accessible.",

  4:
    "Longer narratives, descriptive passages, instructions and simple factual " +
    "texts. Allow more detailed descriptions and basic reasoning questions.",

  5:
    "More detailed narratives, short articles and informational passages. " +
    "Allow simple opinions, contextual vocabulary and basic implied meaning.",

  6:
    "Longer coherent passages including narratives, informational texts, " +
    "descriptions and instructions. Include main idea, supporting details, " +
    "cause/effect, vocabulary in context and basic inference.",
};

const WRITING: Record<
  number,
  {
    complexity: string;
    minWords: number;
  }
> = {
  1: {
    complexity:
      "Words, short phrases and simple subject-predicate sentences. " +
      "Focus on picture-based writing, sentence completion, word " +
      "rearrangement and simple sentence construction.",
    minWords: 0,
  },

  2: {
    complexity:
      "Short guided writing using simple connected sentences. " +
      "Focus on descriptions of familiar activities, people, places " +
      "and short personal experiences.",
    minWords: 0,
  },

  3: {
    complexity:
      "Short narrative, description, future plan or simple explanation. " +
      "Use several connected sentences and increasingly independent " +
      "sentence construction.",
    minWords: 20,
  },

  4: {
    complexity:
      "A connected paragraph involving description, instructions, narrative, " +
      "comparison or giving advice. Require clearer organization and more " +
      "varied Standard 4 grammar.",
    minWords: 40,
  },

  5: {
    complexity:
      "Short article, narrative, description, instructions or simple opinion " +
      "writing with reasons. Increase vocabulary range, organization and " +
      "independence.",
    minWords: 60,
  },

  6: {
    complexity:
      "Multiple connected paragraphs with a clear beginning, middle and end " +
      "where appropriate. Expect developed ideas, broader A2 vocabulary, " +
      "better organization and more independent writing.",
    minWords: 80,
  },
};

function normalizeStandard(standard: number): number {
  if (!Number.isFinite(standard)) {
    return 1;
  }

  return Math.min(Math.max(Math.round(standard), 1), 6);
}

export function standardSyllabus(
  standard: number
): SyllabusContext {
  const s = normalizeStandard(standard);
  const writing = WRITING[s];

  return {
    standard: s,
    year: s,
    cefr: CEFR[s],
    vocabLevel: VOCAB[s],
    allowedGrammar: GRAMMAR[s],
    readingComplexity: READING_COMPLEXITY[s],
    writingComplexity: writing.complexity,
    writingMinWords: writing.minWords,
  };
}
