// ============================================================
// LEXICORE SYLLABUS CONFIGURATION
// ============================================================
//
// Design principles:
// 1. Syllabus information describes WHAT a student at a level
//    should be able to handle.
//
// 2. StudentProfile describes HOW WELL a particular student
//    is currently performing.
//
// 3. The AI prompt should combine both.
//
// 4. Grammar is stored incrementally by Standard and converted
//    into cumulative grammar automatically.
//
// ============================================================


// ============================================================
// TYPES
// ============================================================

export interface ReadingContext {
  complexity: string;
  target: string;

  // Suggested article length for daily reading.
  minWords: number;
  targetWords: number;
  maxWords: number;

  // Expected text types.
  textTypes: string[];

  // Skills that the reading material should support.
  skills: string[];
}

export interface WritingContext {
  complexity: string;
  minWords: number;
  textTypes: string[];
}

export interface SyllabusContext {
  standard: number;

  // Malaysian primary-school year/standard.
  year: number;

  // Approximate CEFR target.
  cefr: string;

  // Vocabulary expectations.
  vocabulary: string;

  // Grammar allowed up to this Standard.
  allowedGrammar: string;

  // Reading requirements.
  reading: ReadingContext;

  // Writing requirements.
  writing: WritingContext;

  // ── Backward-compatible flat aliases ─────────────────────────────────────
  // generate/index.ts, reading/index.ts and writing/index.ts all read these
  // flat field names rather than the nested reading/writing objects above.
  // Kept in sync with reading.complexity / writing.complexity / writing.minWords
  // so none of those functions need to change alongside this richer shape.
  vocabLevel: string;
  readingComplexity: string;
  writingComplexity: string;
  writingMinWords: number; // every Standard now has some minimum (20-120)
}


// ============================================================
// STUDENT PROFILE
// ============================================================
//
// This is NOT part of the syllabus.
// It represents the current student's performance.
//
// Scores are expected to be 0–100.
// null means that the score is unavailable.
//
// ============================================================

export interface StudentProfile {
  standard: number;

  // Keep grade as a separate field because your Flutter
  // application already supplies it.
  //
  // If your "grade" is simply another name for Standard,
  // you can remove this later.
  grade: string;

  rate: number;

  vocabularyScore: number | null;
  grammarScore: number | null;
  readingScore: number | null;
  writingScore: number | null;
}


// ============================================================
// COMPLETE AI CONTEXT
// ============================================================
//
// This is the object you can pass to your prompt builder.
//
// ============================================================

export interface LearningContext {
  student: StudentProfile;
  syllabus: SyllabusContext;
}


// ============================================================
// CEFR
// ============================================================

const CEFR: Record<number, string> = {
  1: "Pre-A1 / A1 Low",
  2: "A1 Low / A1 Mid",
  3: "A1 Mid / A1 High",
  4: "A1 High",
  5: "A2",
  6: "A2",
};


// ============================================================
// VOCABULARY
// ============================================================

const VOCABULARY: Record<number, string> = {

  1:
    "Use very simple everyday vocabulary appropriate to Pre-A1 " +
    "or A1 Low. Prefer concrete, highly familiar words related " +
    "to children, family, school, animals, food, colours, numbers, " +
    "body parts, common objects and simple daily activities. " +
    "Focus mainly on recognition and identification.",

  2:
    "Use simple familiar vocabulary appropriate to A1 Low or A1 Mid. " +
    "Use common everyday words related to school, family, hobbies, " +
    "food, animals, places, routines and simple experiences. " +
    "Strengthen recognition, basic understanding and simple use.",

  3:
    "Use broader vocabulary appropriate to A1 Mid or A1 High. " +
    "Introduce more varied everyday vocabulary and encourage " +
    "understanding from context. Allow basic descriptive words, " +
    "word choice and practical vocabulary use.",

  4:
    "Use A1 High vocabulary with greater range and precision. " +
    "Introduce more descriptive language and less predictable " +
    "word choices while remaining appropriate for primary-school learners.",

  5:
    "Use A2-level vocabulary across a broader range of everyday " +
    "and simple academic contexts. Encourage contextual meaning, " +
    "more precise vocabulary choices and greater independence.",

  6:
    "Use A2-level vocabulary with greater range and flexibility. " +
    "Allow somewhat more abstract and contextual vocabulary. " +
    "Idioms and proverbs may be used when appropriate to the learner."
};


// ============================================================
// INCREMENTAL GRAMMAR
// ============================================================
//
// IMPORTANT:
//
// Each Standard contains ONLY the grammar newly introduced
// at that Standard.
//
// cumulativeGrammar() combines Standards 1..N.
//
// This is better than manually repeating:
// "Everything from Standard 1, plus..."
//
// ============================================================

const GRAMMAR_BY_STANDARD: Record<number, string> = {

  1:
    "Common nouns for people, animals, places and things; " +
    "proper nouns for people, animals, places, days and months; " +
    "singular and plural nouns using s and es; basic countable " +
    "and uncountable noun grouping; articles a and an; " +
    "demonstratives this, that, these and those; subject pronouns " +
    "I, he, she, they, we, you and it; possessive adjectives " +
    "my, your, his, her, its, our and their; possessive nouns " +
    "using 's; subject-verb agreement with am, is and are; " +
    "basic simple present; basic simple past including was, were " +
    "and regular d, ed and ied forms; positive and negative " +
    "statements using no and not; WH-questions what, who and where; " +
    "basic adjectives; basic prepositions under, in, on, at and near; " +
    "simple subject-predicate sentences; conjunctions and and or; " +
    "full stop, comma, question mark and exclamation mark.",

  2:
    "The definite article the; object pronouns me, us, you, them, " +
    "him, her and it; possessive pronouns mine, ours, yours, theirs, " +
    "his and hers; was and were; present continuous using " +
    "am, is or are + verb-ing; WH-questions when and which; " +
    "adjectives of size, shape, colour and quality; expanded " +
    "prepositions of position and direction; conjunctions and, or, " +
    "but and because.",

  3:
    "Additional plural noun forms including ies and ves; " +
    "countable and uncountable quantifiers including a few, several, " +
    "many, some, any, a lot of, a little and much; reflexive pronouns; " +
    "simple future using shall and will; going to for future meaning; " +
    "negative contractions including isn't, aren't, wasn't, weren't, " +
    "doesn't, don't and didn't; WH-questions why, whose and how; " +
    "adjectives ending in -ful, -less and -y; prepositions of time " +
    "at, on and in, including before, after and since; conjunction so; " +
    "basic synonyms and antonyms.",

  4:
    "Additional plural noun form en; expanded countable and " +
    "uncountable quantifiers; comparative and superlative adjectives; " +
    "adverbs of manner, frequency and time; WH-question whom; " +
    "imperatives; conjunctions and linking expressions including " +
    "or, whether, therefore, although, if, unless, while and when; " +
    "modal expressions can, could, shall, should, may, might, must, " +
    "has to and have to.",

  5:
    "Adverbs of place; common age-appropriate idioms; common " +
    "age-appropriate proverbs.",

  6:
    "Comparison of adverbs using positive, comparative and " +
    "superlative forms; prepositions of manner and instrument " +
    "including by and with."
};


// ============================================================
// CUMULATIVE GRAMMAR
// ============================================================

function cumulativeGrammar(
  standard: number
): string {

  const sections: string[] = [];

  for (let level = 1; level <= standard; level++) {
    sections.push(
      `Standard ${level}: ${GRAMMAR_BY_STANDARD[level]}`
    );
  }

  return sections.join("\n");
}


// ============================================================
// READING
// ============================================================
//
// This is specifically designed to support your Daily Reading
// module.
//
// Word counts are targets rather than absolute requirements.
// Your article generator should validate the final article
// separately.
//
// ============================================================

const READING: Record<number, ReadingContext> = {

  1: {
    complexity:
      "Use very short sentences with concrete and highly familiar " +
      "topics. Use simple sentence structures and direct information. " +
      "Avoid complex clauses, advanced vocabulary and idioms.",

    target:
      "Build confidence reading short sentences and identifying " +
      "explicit information.",

    minWords: 40,
    targetWords: 60,
    maxWords: 80,

    textTypes: [
      "very short story",
      "simple description",
      "simple daily-life passage"
    ],

    skills: [
      "recognise familiar words",
      "identify explicit information",
      "understand simple sentences",
      "follow basic sequence"
    ],
  },

  2: {
    complexity:
      "Use short passages slightly longer than Standard 1. " +
      "Use familiar school, family, hobby, animal and everyday " +
      "contexts. Simple present, simple past and present continuous " +
      "may be used where appropriate.",

    target:
      "Understand short passages and identify simple details " +
      "and sequence.",

    minWords: 120,
    targetWords: 160,
    maxWords: 200,

    textTypes: [
      "short story",
      "simple description",
      "simple informational passage"
    ],

    skills: [
      "identify key details",
      "follow sequence",
      "understand familiar vocabulary in context",
      "identify simple actions and events"
    ],
  },

  3: {
    complexity:
      "Use short narratives, simple explanations and short " +
      "informational texts. Introduce sequencing, simple " +
      "cause-and-effect relationships, comparisons and basic " +
      "inference while keeping language accessible.",

    target:
      "Understand short narratives and informational texts while " +
      "identifying sequence, simple cause and effect, comparisons " +
      "and basic inference.",

    minWords: 220,
    targetWords: 260,
    maxWords: 310,

    textTypes: [
      "short narrative",
      "informational text",
      "simple explanation",
      "descriptive passage"
    ],

    skills: [
      "identify main ideas",
      "identify supporting details",
      "follow sequence",
      "recognise simple cause and effect",
      "make basic inferences",
      "understand vocabulary from context"
    ],
  },

  4: {
    complexity:
      "Use longer narratives, descriptive passages, instructions " +
      "and simple factual texts. Allow more detailed descriptions, " +
      "comparisons and basic reasoning.",

    target:
      "Understand descriptive and factual texts while identifying " +
      "key details and simple reasoning.",

    minWords: 310,
    targetWords: 360,
    maxWords: 430,

    textTypes: [
      "narrative",
      "descriptive text",
      "instructions",
      "factual passage"
    ],

    skills: [
      "identify main ideas",
      "identify supporting details",
      "understand sequence",
      "understand comparisons",
      "recognise simple cause and effect",
      "make basic inferences"
    ],
  },

  5: {
    complexity:
      "Use more detailed narratives, short articles and informational " +
      "passages. Allow simple opinions, contextual vocabulary and " +
      "basic implied meaning.",

    target:
      "Identify main ideas, supporting details, contextual vocabulary " +
      "and simple implied meaning.",

    minWords: 410,
    targetWords: 460,
    maxWords: 550,

    textTypes: [
      "narrative",
      "short article",
      "informational text",
      "descriptive text"
    ],

    skills: [
      "identify main idea",
      "identify supporting details",
      "understand vocabulary in context",
      "recognise implied meaning",
      "understand cause and effect",
      "make simple inferences"
    ],
  },

  6: {
    complexity:
      "Use longer coherent passages including narratives, " +
      "informational texts, descriptions and instructions. " +
      "Allow broader vocabulary, varied sentence structures, " +
      "main ideas, supporting details, cause and effect and " +
      "basic inference.",

    target:
      "Identify main ideas, supporting details, cause and effect, " +
      "vocabulary in context and basic inference.",

    minWords: 500,
    targetWords: 560,
    maxWords: 650,

    textTypes: [
      "narrative",
      "informational article",
      "description",
      "instructions"
    ],

    skills: [
      "identify main ideas",
      "identify supporting details",
      "understand cause and effect",
      "interpret vocabulary in context",
      "recognise implied meaning",
      "make basic inferences"
    ],
  },
};


// ============================================================
// WRITING
// ============================================================

const WRITING: Record<number, WritingContext> = {

  1: {
    complexity:
      "Use words, short phrases and simple subject-predicate " +
      "sentences. Focus on picture-based writing, sentence " +
      "completion, word rearrangement and simple sentence construction.",

    minWords: 20,

    textTypes: [
      "sentence completion",
      "word rearrangement",
      "picture-based sentence",
      "simple sentence"
    ],
  },

  2: {
    complexity:
      "Use short guided writing with simple connected sentences. " +
      "Focus on descriptions of familiar activities, people, " +
      "places and short personal experiences.",

    minWords: 30,

    textTypes: [
      "short description",
      "personal experience",
      "guided paragraph",
      "simple sequence"
    ],
  },

  3: {
    complexity:
      "Use short narratives, descriptions, future plans and " +
      "simple explanations. Require several connected sentences " +
      "and increasingly independent sentence construction.",

    minWords: 50,

    textTypes: [
      "short narrative",
      "description",
      "future plan",
      "simple explanation"
    ],
  },

  4: {
    complexity:
      "Use connected paragraphs involving description, instructions, " +
      "narrative, comparison or advice. Require clearer organization " +
      "and more varied Standard 4 grammar.",

    minWords: 80,

    textTypes: [
      "description",
      "instructions",
      "narrative",
      "comparison",
      "advice"
    ],
  },

  5: {
    complexity:
      "Use short articles, narratives, descriptions, instructions " +
      "or simple opinion writing with reasons. Increase vocabulary " +
      "range, organization and independence.",

    minWords: 100,

    textTypes: [
      "short article",
      "narrative",
      "description",
      "instructions",
      "simple opinion"
    ],
  },

  6: {
    complexity:
      "Use multiple connected paragraphs where appropriate. " +
      "Expect developed ideas, broader A2 vocabulary, clearer " +
      "organization and more independent writing.",

    minWords: 120,

    textTypes: [
      "article",
      "narrative",
      "description",
      "instructions",
      "opinion writing"
    ],
  },
};


// ============================================================
// STANDARD NORMALISATION
// ============================================================

export function normalizeStandard(
  value: unknown
): number {

  const number =
    Number(value);

  if (
    !Number.isFinite(number)
  ) {
    return 1;
  }

  return Math.min(
    Math.max(
      Math.round(number),
      1
    ),
    6
  );
}


// ============================================================
// SCORE NORMALISATION
// ============================================================

export function normalizeScore(
  value: unknown
): number | null {

  if (
    value === null ||
    value === undefined ||
    value === ""
  ) {
    return null;
  }

  const number =
    Number(value);

  if (
    !Number.isFinite(number)
  ) {
    return null;
  }

  return Math.min(
    Math.max(number, 0),
    100
  );
}


// ============================================================
// RATE NORMALISATION
// ============================================================

export function normalizeRate(
  value: unknown
): number {

  const number =
    Number(value);

  if (
    !Number.isFinite(number)
  ) {
    return 0;
  }

  return Math.min(
    Math.max(number, 0),
    100
  );
}


// ============================================================
// GRADE NORMALISATION
// ============================================================
//
// Your Flutter application currently sends grade as String.
//
// This function accepts either a string or number.
//
// ============================================================

export function normalizeGrade(
  value: unknown,
  standard: number
): string {

  if (
    value === null ||
    value === undefined
  ) {
    return String(standard);
  }

  const grade =
    String(value).trim();

  return grade.length > 0
    ? grade
    : String(standard);
}


// ============================================================
// SYLLABUS LOOKUP
// ============================================================

export function standardSyllabus(
  standard: number
): SyllabusContext {

  const s =
    normalizeStandard(
      standard
    );

  const reading = READING[s];
  const writing = WRITING[s];

  return {
    standard: s,

    year: s,

    cefr:
      CEFR[s],

    vocabulary:
      VOCABULARY[s],

    allowedGrammar:
      cumulativeGrammar(s),

    reading,

    writing,

    // Flat aliases kept in sync with the nested values above — see the
    // SyllabusContext comment for why these exist.
    vocabLevel: VOCABULARY[s],
    readingComplexity: reading.complexity,
    writingComplexity: writing.complexity,
    writingMinWords: writing.minWords,
  };
}


// ============================================================
// STUDENT PROFILE BUILDER
// ============================================================

export function createStudentProfile(
  input: {
    standard: unknown;
    grade?: unknown;
    rate?: unknown;

    vocabulary_score?: unknown;
    grammar_score?: unknown;
    reading_score?: unknown;
    writing_score?: unknown;
  }
): StudentProfile {

  const standard =
    normalizeStandard(
      input.standard
    );

  return {
    standard,

    grade:
      normalizeGrade(
        input.grade,
        standard
      ),

    rate:
      normalizeRate(
        input.rate
      ),

    vocabularyScore:
      normalizeScore(
        input.vocabulary_score
      ),

    grammarScore:
      normalizeScore(
        input.grammar_score
      ),

    readingScore:
      normalizeScore(
        input.reading_score
      ),

    writingScore:
      normalizeScore(
        input.writing_score
      ),
  };
}


// ============================================================
// LEARNING CONTEXT BUILDER
// ============================================================

export function createLearningContext(
  input: {
    standard: unknown;
    grade?: unknown;
    rate?: unknown;

    vocabulary_score?: unknown;
    grammar_score?: unknown;
    reading_score?: unknown;
    writing_score?: unknown;
  }
): LearningContext {

  const student =
    createStudentProfile(
      input
    );

  const syllabus =
    standardSyllabus(
      student.standard
    );

  return {
    student,
    syllabus,
  };
}


// ============================================================
// READING PROMPT CONTEXT
// ============================================================
//
// This is especially useful for your Daily Reading Edge Function.
//
// ============================================================

export function buildReadingContext(
  context: LearningContext
): string {

  const {
    student,
    syllabus,
  } = context;

  const reading =
    syllabus.reading;

  return `
STUDENT PROFILE

Standard:
${student.standard}

Grade:
${student.grade}

Overall Rate:
${student.rate}/100

Vocabulary Score:
${
  student.vocabularyScore === null
    ? "Not available"
    : `${student.vocabularyScore}/100`
}

Grammar Score:
${
  student.grammarScore === null
    ? "Not available"
    : `${student.grammarScore}/100`
}

Reading Score:
${
  student.readingScore === null
    ? "Not available"
    : `${student.readingScore}/100`
}

Writing Score:
${
  student.writingScore === null
    ? "Not available"
    : `${student.writingScore}/100`
}


SYLLABUS CONTEXT

CEFR:
${syllabus.cefr}

Vocabulary Level:
${syllabus.vocabulary}

Reading Complexity:
${reading.complexity}

Reading Target:
${reading.target}

Suggested Word Count:
${reading.minWords}–${reading.maxWords}

Suitable Text Types:
${reading.textTypes.join(", ")}

Reading Skills:
${reading.skills.join(", ")}

Allowed Grammar:
${syllabus.allowedGrammar}
`.trim();
}


// ============================================================
// EXPORTS FOR OTHER MODULES
// ============================================================

export {
  CEFR,
  VOCABULARY,
  GRAMMAR_BY_STANDARD,
  READING,
  WRITING,
};