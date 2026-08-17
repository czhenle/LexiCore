import OpenAI from "npm:openai";
import { createClient } from "npm:@supabase/supabase-js@2";

// ============================================================
// CORS
// ============================================================

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods":
    "POST, OPTIONS",
};

// ============================================================
// RESPONSE HELPER
// ============================================================

function jsonResponse(
  data: unknown,
  status = 200
): Response {
  return new Response(
    JSON.stringify(data),
    {
      status,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
      },
    }
  );
}

// ============================================================
// TYPES
// ============================================================

type VocabularyHint = {
  word: string;
  meaning: string;
};

type ReadingArticle = {
  title: string;
  topic: string;
  level: number;
  word_count: number;
  body: string;
  hints: VocabularyHint[];
};

type RecentArticle = {
  id: string;
  reading_date: string;
  title: string;
  topic: string;
};

// ============================================================
// WORD TARGETS
// ============================================================

const wordTargets: Record<number, number> = {
  1: 60,
  2: 160,
  3: 260,
  4: 360,
  5: 460,
  6: 560,
};

// ============================================================
// TOPICS
// ============================================================

const topics = [
  "School Life",
  "Family and Home",
  "Animals in Malaysia",
  "Food and Cooking",
  "Festivals in Malaysia",
  "The Environment",
  "Sports and Games",
  "Community Helpers",
  "Technology",
  "Travel and Places",
  "Health and the Body",
  "Hobbies",
  "Friendship",
  "Nature",
  "Weather",
  "Helping Others",
];

// ============================================================
// CONFIGURATION
// ============================================================

const WORD_COUNT_TOLERANCE = 0.12;

const RECENT_ARTICLE_LIMIT = 10;

// How many times a student may swap today's article for a new one.
// 2 = up to 3 stories/day total (the first one + 2 regenerations).
const MAX_REGENERATIONS_PER_DAY = 2;

// ============================================================
// SUPABASE CLIENT
// ============================================================

function createSupabaseClient(req: Request) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseKey = Deno.env.get("SUPABASE_ANON_KEY");

  if (!supabaseUrl || !supabaseKey) {
    throw new Error(
      "Supabase environment variables are not configured."
    );
  }

  const authorization =
    req.headers.get("Authorization");

  if (!authorization) {
    throw new Error(
      "Missing Authorization header."
    );
  }

  return createClient(
    supabaseUrl,
    supabaseKey,
    {
      global: {
        headers: {
          Authorization: authorization,
        },
      },
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    }
  );
}

// ============================================================
// OPENAI CLIENT
// ============================================================

function createOpenAIClient(): OpenAI {
  const apiKey =
    Deno.env.get("OPENAI_API_KEY");

  if (!apiKey) {
    throw new Error(
      "OPENAI_API_KEY is not configured."
    );
  }

  return new OpenAI({
    apiKey,
  });
}

// ============================================================
// DATE
// ============================================================
//
// Daily reading should follow Malaysia time rather than UTC.
//
// Example:
// If Malaysia is already August 18 while UTC is still August 17,
// the student should receive the August 18 article.
//

function getMalaysiaDate(): string {
  return new Intl.DateTimeFormat(
    "en-CA",
    {
      timeZone: "Asia/Kuala_Lumpur",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }
  ).format(new Date());
}

// ============================================================
// NUMBER HELPERS
// ============================================================

function clampStandard(
  value: unknown
): number {
  const parsed = Number(value);

  if (!Number.isFinite(parsed)) {
    return 3;
  }

  return Math.min(
    Math.max(
      Math.round(parsed),
      1
    ),
    6
  );
}

function normaliseScore(
  value: unknown
): number | null {
  if (
    value === null ||
    value === undefined ||
    value === ""
  ) {
    return null;
  }

  const parsed = Number(value);

  if (!Number.isFinite(parsed)) {
    return null;
  }

  return Math.min(
    Math.max(parsed, 0),
    100
  );
}

// ============================================================
// WORD COUNT
// ============================================================

function countWords(
  text: string
): number {
  return text
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .length;
}

// ============================================================
// WORD COUNT RANGE
// ============================================================

function getWordRange(
  target: number
) {
  return {
    min: Math.floor(
      target *
      (1 - WORD_COUNT_TOLERANCE)
    ),

    max: Math.ceil(
      target *
      (1 + WORD_COUNT_TOLERANCE)
    ),
  };
}

// ============================================================
// TOPIC SELECTION
// ============================================================

function chooseTopic(
  recentTopics: string[]
): string {

  const recentSet =
    new Set(
      recentTopics.map(
        (topic) =>
          topic.toLowerCase()
      )
    );

  const availableTopics =
    topics.filter(
      (topic) =>
        !recentSet.has(
          topic.toLowerCase()
        )
    );

  const pool =
    availableTopics.length > 0
      ? availableTopics
      : topics;

  return pool[
    Math.floor(
      Math.random() *
      pool.length
    )
  ];
}

// ============================================================
// VALIDATE VOCABULARY HINT
// ============================================================

function isValidHint(
  value: unknown
): value is VocabularyHint {

  if (
    !value ||
    typeof value !== "object"
  ) {
    return false;
  }

  const hint =
    value as Record<string, unknown>;

  return (
    typeof hint.word === "string" &&
    hint.word.trim().length > 0 &&
    typeof hint.meaning === "string" &&
    hint.meaning.trim().length > 0
  );
}

// ============================================================
// VALIDATE ARTICLE
// ============================================================

function validateArticle(
  value: unknown,
  standard: number,
  target: number
): value is ReadingArticle {

  if (
    !value ||
    typeof value !== "object"
  ) {
    return false;
  }

  const article =
    value as Record<string, unknown>;

  if (
    typeof article.title !== "string" ||
    article.title.trim().length === 0
  ) {
    return false;
  }

  if (
    typeof article.topic !== "string" ||
    article.topic.trim().length === 0
  ) {
    return false;
  }

  if (
    typeof article.body !== "string" ||
    article.body.trim().length === 0
  ) {
    return false;
  }

  if (
    !Array.isArray(article.hints)
  ) {
    return false;
  }

  if (
    article.hints.length < 5 ||
    article.hints.length > 8
  ) {
    return false;
  }

  if (
    !article.hints.every(
      isValidHint
    )
  ) {
    return false;
  }

  const actualWordCount =
    countWords(
      article.body
    );

  const {
    min,
    max,
  } = getWordRange(target);

  if (
    actualWordCount < min ||
    actualWordCount > max
  ) {
    return false;
  }

  // Ensure every vocabulary word
  // actually appears in the article.
  const articleText =
    article.body.toLowerCase();

  for (
    const hint of article.hints
  ) {

    if (
      !articleText.includes(
        hint.word.toLowerCase()
      )
    ) {
      return false;
    }
  }

  return true;
}

// ============================================================
// NORMALISE ARTICLE
// ============================================================

function normaliseArticle(
  article: ReadingArticle,
  standard: number
): ReadingArticle {

  const body =
    article.body
      .trim()
      .replace(
        /\r\n/g,
        "\n"
      )
      .replace(
        /\n{3,}/g,
        "\n\n"
      );

  return {
    title:
      article.title.trim(),

    topic:
      article.topic.trim(),

    level:
      standard,

    word_count:
      countWords(body),

    body,

    hints:
      article.hints
        .slice(0, 8)
        .map(
          (hint) => ({
            word:
              hint.word.trim(),

            meaning:
              hint.meaning.trim(),
          })
        ),
  };
}

// ============================================================
// READ TODAY'S ARTICLE
// ============================================================

async function getTodayArticle(
  supabase: ReturnType<
    typeof createSupabaseClient
  >,
  userId: string,
  today: string
) {

  const {
    data,
    error,
  } = await supabase
    .from("recent_articles")
    .select(
      `
        id,
        reading_date,
        standard,
        grade,
        rate,
        vocabulary_score,
        grammar_score,
        reading_score,
        writing_score,
        title,
        topic,
        body,
        word_count,
        hints,
        regenerations,
        created_at
      `
    )
    .eq(
      "user_id",
      userId
    )
    .eq(
      "reading_date",
      today
    )
    .maybeSingle();

  if (error) {
    throw error;
  }

  return data;
}

// ============================================================
// READ RECENT ARTICLES
// ============================================================

async function getRecentArticles(
  supabase: ReturnType<
    typeof createSupabaseClient
  >,
  userId: string
): Promise<RecentArticle[]> {

  const {
    data,
    error,
  } = await supabase
    .from("recent_articles")
    .select(
      `
        id,
        reading_date,
        title,
        topic
      `
    )
    .eq(
      "user_id",
      userId
    )
    .order(
      "reading_date",
      {
        ascending: false,
      }
    )
    .limit(
      RECENT_ARTICLE_LIMIT
    );

  if (error) {
    throw error;
  }

  return (data ?? []) as RecentArticle[];
}

// ============================================================
// BUILD PROMPT
// ============================================================

function buildPrompt({
  standard,
  grade,
  rate,
  vocabularyScore,
  grammarScore,
  readingScore,
  writingScore,
  topic,
  target,
  recentTopics,
}: {
  standard: number;
  grade: string;
  rate: string;
  vocabularyScore: number | null;
  grammarScore: number | null;
  readingScore: number | null;
  writingScore: number | null;
  topic: string;
  target: number;
  recentTopics: string[];
}): string {

  const {
    min,
    max,
  } = getWordRange(target);

  return `
You are Lexi, a friendly English reading tutor
for a Malaysian primary school student.

Generate ONE daily reading article.

==================================================
STUDENT INFORMATION
==================================================

Standard: ${standard}
Grade: ${grade}
Self-rated skills (1-5 each): ${rate}

Vocabulary score:
${
  vocabularyScore === null
    ? "Not available"
    : `${vocabularyScore}/100`
}

Grammar score:
${
  grammarScore === null
    ? "Not available"
    : `${grammarScore}/100`
}

Reading score:
${
  readingScore === null
    ? "Not available"
    : `${readingScore}/100`
}

Writing score:
${
  writingScore === null
    ? "Not available"
    : `${writingScore}/100`
}

==================================================
ARTICLE
==================================================

Topic:
${topic}

Target:
approximately ${target} words

Acceptable:
${min}–${max} words

==================================================
WRITING RULES
==================================================

1. Write ONE meaningful reading article.

2. The article must have:
   - an introduction
   - a clear middle
   - a satisfying ending

3. Do NOT write a list of facts.

4. Use simple English appropriate for Standard ${standard}.

5. Use British English spelling where appropriate.

6. Use clear paragraphs.

7. The article should be interesting enough
   for a primary school student to read daily.

8. Use Malaysian culture or daily life naturally
   where appropriate.

9. Do not force Malaysian references.

10. Do not include:
    - comprehension questions
    - exercises
    - quizzes
    - answers
    - activities
    - teacher notes
    - explanations outside the article

==================================================
VOCABULARY
==================================================

Include 5–8 useful vocabulary words naturally.

The vocabulary words must:

- actually appear in the article
- be slightly challenging
- still be suitable for the student's level
- help the student learn English

Do not use extremely basic words such as:
good, bad, nice, happy, big, small.

Give a very simple meaning for each word.

==================================================
PERSONALISATION
==================================================

Use the student's scores to control difficulty.

If reading score is low:
- use shorter sentences
- make ideas easier to follow
- use simpler vocabulary

If reading score is high:
- use more varied sentence structures
- slightly increase reading complexity

If vocabulary score is low:
- keep most vocabulary familiar
- introduce only a few challenging words

If vocabulary score is high:
- introduce somewhat richer vocabulary

Grammar and writing scores may also be
considered when choosing sentence complexity.

==================================================
RECENT TOPICS
==================================================

Recently generated topics:

${
  recentTopics.length > 0
    ? recentTopics.join(", ")
    : "None"
}

Avoid repeating a recent topic whenever possible.

==================================================
OUTPUT
==================================================

Return ONLY valid JSON.

Use exactly this structure:

{
  "title": "Article title",
  "topic": "${topic}",
  "level": ${standard},
  "word_count": 0,
  "body": "Full article text",
  "hints": [
    {
      "word": "vocabulary word",
      "meaning": "simple meaning"
    }
  ]
}

Important:
- Return 5–8 hints.
- Every hint must appear in the body.
- word_count must equal the number of words in body.
- Return JSON only.
`;
}

// ============================================================
// GENERATE ARTICLE
// ============================================================

async function generateArticle({
  openai,
  standard,
  grade,
  rate,
  vocabularyScore,
  grammarScore,
  readingScore,
  writingScore,
  topic,
  recentTopics,
}: {
  openai: OpenAI;
  standard: number;
  grade: string;
  rate: string;
  vocabularyScore: number | null;
  grammarScore: number | null;
  readingScore: number | null;
  writingScore: number | null;
  topic: string;
  recentTopics: string[];
}): Promise<ReadingArticle> {

  const target =
    wordTargets[standard] ??
    wordTargets[3];

  const prompt =
    buildPrompt({
      standard,
      grade,
      rate,
      vocabularyScore,
      grammarScore,
      readingScore,
      writingScore,
      topic,
      target,
      recentTopics,
    });

  const response =
    await openai.responses.create({
      model: "gpt-5.6-luna",

      instructions:
        "You generate daily reading material for LexiCore. Follow the user's output format exactly. Return valid JSON only.",

      input: prompt,

      reasoning: {
        effort: "low",
      },

      text: {
        format: {
          type: "json_object",
        },
      },
    });

  const raw =
    response.output_text?.trim() ??
    "";

  if (!raw) {
    throw new Error(
      "OpenAI returned an empty response."
    );
  }

  let parsed: unknown;

  try {
    parsed =
      JSON.parse(raw);
  } catch {
    throw new Error(
      "OpenAI returned invalid JSON."
    );
  }

  if (
    !validateArticle(
      parsed,
      standard,
      target
    )
  ) {
    throw new Error(
      "Generated article failed validation."
    );
  }

  return normaliseArticle(
    parsed,
    standard
  );
}

// ============================================================
// STORE ARTICLE
// ============================================================

async function storeArticle({
  supabase,
  userId,
  today,
  standard,
  grade,
  rate,
  vocabularyScore,
  grammarScore,
  readingScore,
  writingScore,
  article,
}: {
  supabase: ReturnType<
    typeof createSupabaseClient
  >;
  userId: string;
  today: string;
  standard: number;
  grade: string;
  rate: string;
  vocabularyScore: number | null;
  grammarScore: number | null;
  readingScore: number | null;
  writingScore: number | null;
  article: ReadingArticle;
}) {

  const {
    data,
    error,
  } = await supabase
    .from("recent_articles")
    .insert({
      user_id: userId,

      reading_date: today,

      standard,

      grade,

      rate,

      vocabulary_score:
        vocabularyScore,

      grammar_score:
        grammarScore,

      reading_score:
        readingScore,

      writing_score:
        writingScore,

      title:
        article.title,

      topic:
        article.topic,

      body:
        article.body,

      word_count:
        article.word_count,

      hints:
        article.hints,
    })
    .select()
    .single();

  if (error) {
    throw error;
  }

  return data;
}

// ============================================================
// REGENERATE ARTICLE (overwrite today's row, keep the same day)
// ============================================================
//
// Used when the student taps "New Story" after already having one today.
// The unique(user_id, reading_date) constraint means there is still only
// ONE row per day — this UPDATEs it instead of inserting a second row, and
// bumps `regenerations` so the cap in the main handler can be enforced.
//
// Note: the increment below is read-then-write (existingRegenerations + 1),
// not a single atomic SQL expression. For a single student tapping the
// button that's negligible risk; a rapid double-tap could in theory count
// as one extra regeneration. Acceptable for this app's scale — an atomic
// Postgres function/RPC would remove even that if it's ever needed.
//
async function regenerateArticle({
  supabase,
  articleId,
  existingRegenerations,
  standard,
  grade,
  rate,
  vocabularyScore,
  grammarScore,
  readingScore,
  writingScore,
  article,
}: {
  supabase: ReturnType<
    typeof createSupabaseClient
  >;
  articleId: string;
  existingRegenerations: number;
  standard: number;
  grade: string;
  rate: string;
  vocabularyScore: number | null;
  grammarScore: number | null;
  readingScore: number | null;
  writingScore: number | null;
  article: ReadingArticle;
}) {

  const {
    data,
    error,
  } = await supabase
    .from("recent_articles")
    .update({
      standard,
      grade,
      rate,
      vocabulary_score: vocabularyScore,
      grammar_score: grammarScore,
      reading_score: readingScore,
      writing_score: writingScore,
      title: article.title,
      topic: article.topic,
      body: article.body,
      word_count: article.word_count,
      hints: article.hints,
      regenerations: existingRegenerations + 1,
    })
    .eq("id", articleId)
    .select()
    .single();

  if (error) {
    throw error;
  }

  return data;
}

// ============================================================
// MAIN SERVER
// ============================================================

Deno.serve(
  async (req: Request) => {

    // --------------------------------------------------------
    // CORS
    // --------------------------------------------------------

    if (
      req.method === "OPTIONS"
    ) {
      return new Response(
        "ok",
        {
          headers:
            corsHeaders,
        }
      );
    }

    // --------------------------------------------------------
    // METHOD
    // --------------------------------------------------------

    if (
      req.method !== "POST"
    ) {
      return jsonResponse(
        {
          success: false,
          error:
            "METHOD_NOT_ALLOWED",
        },
        405
      );
    }

    try {

      // ======================================================
      // CREATE CLIENTS
      // ======================================================

      const supabase =
        createSupabaseClient(
          req
        );

      const openai =
        createOpenAIClient();

      // ======================================================
      // AUTHENTICATED USER
      // ======================================================

      const {
        data: {
          user,
        },
        error: authError,
      } =
        await supabase.auth.getUser();

      if (
        authError ||
        !user
      ) {
        return jsonResponse(
          {
            success: false,
            error:
              "UNAUTHENTICATED",
            message:
              "Please sign in before requesting daily reading.",
          },
          401
        );
      }

      const userId =
        user.id;

      // ======================================================
      // REQUEST BODY
      // ======================================================

      const requestBody =
        await req.json();

      // ------------------------------------------------------
      // PARAMETERS REQUESTED BY USER
      // ------------------------------------------------------

      const standard =
        clampStandard(
          requestBody.standard
        );

      const grade: string =
        typeof requestBody.grade === "string" && requestBody.grade.trim().length > 0
          ? requestBody.grade.trim()
          : "C"; // crash-guard only — grade is required upstream

      const rate: string =
        typeof requestBody.rate === "string" && requestBody.rate.trim().length > 0
          ? requestBody.rate.trim()
          : "{}";

      const vocabularyScore =
        normaliseScore(
          requestBody.vocabulary_score
        );

      const grammarScore =
        normaliseScore(
          requestBody.grammar_score
        );

      const readingScore =
        normaliseScore(
          requestBody.reading_score
        );

      const writingScore =
        normaliseScore(
          requestBody.writing_score
        );

      const force: boolean =
        requestBody.force === true;

      // ======================================================
      // TODAY
      // ======================================================

      const today =
        getMalaysiaDate();

      // ======================================================
      // 1. CHECK TODAY'S ARTICLE
      // ======================================================

      const existingArticle =
        await getTodayArticle(
          supabase,
          userId,
          today
        );

      if (
        existingArticle &&
        !force
      ) {

        return jsonResponse({
          success: true,
          is_new: false,
          source:
            "stored_article",
          article:
            existingArticle,
        });
      }

      // Regeneration requested but today's story has already been
      // swapped the maximum number of times — keep today's article,
      // don't spend another OpenAI call.
      if (
        existingArticle &&
        force &&
        (existingArticle.regenerations ?? 0) >= MAX_REGENERATIONS_PER_DAY
      ) {

        return jsonResponse({
          success: false,
          error: "REGEN_LIMIT_REACHED",
          message:
            "You've used all your new stories for today! Come back tomorrow. 😊",
          article:
            existingArticle,
        }, 429);
      }

      // ======================================================
      // 2. GET RECENT ARTICLES
      // ======================================================

      const recentArticles =
        await getRecentArticles(
          supabase,
          userId
        );

      const recentTopics =
        recentArticles.map(
          (article) =>
            article.topic
        );

      if (
        existingArticle &&
        force
      ) {
        // Don't hand back the same topic we're replacing.
        recentTopics.push(
          existingArticle.topic
        );
      }

      // ======================================================
      // 3. CHOOSE NEW TOPIC
      // ======================================================

      const topic =
        chooseTopic(
          recentTopics
        );

      // ======================================================
      // 4. GENERATE
      // ======================================================

      const article =
        await generateArticle({
          openai,

          standard,

          grade,

          rate,

          vocabularyScore,

          grammarScore,

          readingScore,

          writingScore,

          topic,

          recentTopics,
        });

      // ======================================================
      // 5. STORE
      // ======================================================

      let storedArticle;

      if (
        existingArticle &&
        force
      ) {

        // Regeneration: overwrite today's row, keep the same day.
        storedArticle =
          await regenerateArticle({
            supabase,

            articleId:
              existingArticle.id,

            existingRegenerations:
              existingArticle.regenerations ?? 0,

            standard,

            grade,

            rate,

            vocabularyScore,

            grammarScore,

            readingScore,

            writingScore,

            article,
          });

      } else {

      try {

        storedArticle =
          await storeArticle({
            supabase,

            userId,

            today,

            standard,

            grade,

            rate,

            vocabularyScore,

            grammarScore,

            readingScore,

            writingScore,

            article,
          });

      } catch (insertError) {

        // ----------------------------------------------------
        // CONCURRENCY PROTECTION
        // ----------------------------------------------------
        //
        // Two requests could arrive at almost the same time.
        //
        // Request A → doesn't find today's article
        // Request B → doesn't find today's article
        // Both generate articles
        // Both try to insert
        //
        // The UNIQUE constraint prevents two stored articles.
        //
        // In that case, simply read today's existing article.
        //

        console.warn(
          "Article insert failed. Checking whether today's article already exists.",
          insertError
        );

        const existingAfterInsert =
          await getTodayArticle(
            supabase,
            userId,
            today
          );

        if (
          existingAfterInsert
        ) {
          return jsonResponse({
            success: true,
            is_new: false,
            source:
              "stored_article_after_race",
            article:
              existingAfterInsert,
          });
        }

        throw insertError;
      }

      } // end insert-vs-regenerate branch

      // ======================================================
      // 6. RETURN NEW ARTICLE
      // ======================================================

      return jsonResponse({
        success: true,
        is_new: true,
        source:
          (existingArticle && force)
            ? "regenerated_article"
            : "generated_article",
        article:
          storedArticle,
      });

    } catch (error) {

      // ======================================================
      // SERVER LOG
      // ======================================================

      console.error(
        "Daily reading error:",
        error
      );

      // ======================================================
      // SAFE CLIENT ERROR
      // ======================================================

      return jsonResponse(
        {
          success: false,
          error:
            "DAILY_READING_FAILED",
          message:
            "We could not prepare today's reading article. Please try again.",
        },
        500
      );
    }
  }
);