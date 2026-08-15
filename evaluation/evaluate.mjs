#!/usr/bin/env node
// ============================================================================
// LexiCore — Generation Quality Evaluation  (Node 18+, zero dependencies)
// ----------------------------------------------------------------------------
// Batch-calls your DEPLOYED `generate` function across the taxonomy, then has an
// INDEPENDENT (stronger) judge model score each item against a rubric.
//
// Supports MULTIPLE RUNS with averaging (LLM output varies, so average a few),
// a WIDE sample (all rungs, several sub-skills, optional extra standards), and
// writes a small HAND-CHECK sample so you can report a human/judge agreement
// rate.
//
// Usage:
//   SUPABASE_URL=... SUPABASE_ANON_KEY=... OPENAI_API_KEY=... \
//   node evaluate.mjs --runs 3
//   node evaluate.mjs --dry-run --runs 2     # mocked, no keys (pipeline test)
//   JUDGE_MODEL=gpt-4o node evaluate.mjs     # change the judge
// ============================================================================

import { writeFileSync } from "node:fs";

const DRY = process.argv.includes("--dry-run");
const runsArg = process.argv.indexOf("--runs");
const RUNS = runsArg >= 0 ? Math.max(1, parseInt(process.argv[runsArg + 1] || "1")) : 1;
const HANDCHECK = 5; // items written out for manual verification

const SUPABASE_URL = process.env.SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY;
const OPENAI_KEY = process.env.OPENAI_API_KEY;
const JUDGE_MODEL = process.env.JUDGE_MODEL || "gpt-4.1"; // stronger than the mini generator

if (!DRY && (!SUPABASE_URL || !ANON || !OPENAI_KEY)) {
  console.error("Set SUPABASE_URL, SUPABASE_ANON_KEY, OPENAI_API_KEY (or use --dry-run).");
  process.exit(1);
}

// Rung -> format per skill (mirrors rung_formats seed).
const FORMATS = {
  Vocabulary: ["meaning_match", "mcq_word_meaning", "cloze_sentence_wordbank", "cloze_paragraph_open", "open_sentence"],
  Grammar:    ["worked_example", "mcq_identify_or_error", "gap_fill", "transform_or_reorder", "open_sentence"],
  Reading:    ["vocab_preview", "mcq_literal", "sequence_order", "mcq_inference", "open_response"],
  Writing:    ["punctuation_fix", "sentence_complete", "sentence_combine", "guided_composition", "free_composition"],
};

// ── WIDE sample: 3 sub-skills per skill × all rungs 1–5. Edit freely. ────────
const SUBSKILLS = {
  Vocabulary: [["vocab.food_drink", "Food & Drink"], ["vocab.animals_nature", "Animals & Nature"], ["vocab.feelings", "Feelings & Emotions"]],
  Grammar:    [["grammar.past_tense", "Past Tense"], ["grammar.articles", "Articles (a/an/the)"], ["grammar.sva", "Subject-Verb Agreement"]],
  Reading:    [["reading.literal", "Literal Comprehension"], ["reading.inference", "Inference"], ["reading.sequencing", "Sequencing Events"]],
  Writing:    [["writing.mechanics", "Punctuation & Capitalisation"], ["writing.sentence_combining", "Sentence Combining"], ["writing.spelling", "Spelling"]],
};
const RUNGS = [1, 3, 4];   // all rungs (rung 1 is exposure-type — may score differently)
const STANDARDS = [3];           // add e.g. [2, 4] for a second/third standard

const STANDARD_BASE = { 1: 1000, 2: 1080, 3: 1160, 4: 1240, 5: 1320, 6: 1400 };
const RUNG_OFFSET = { 1: -240, 2: -160, 3: -80, 4: 0, 5: 80 };

function buildSample() {
  const out = [];
  for (const standard of STANDARDS) {
    for (const [skill, subs] of Object.entries(SUBSKILLS)) {
      for (const [code, name] of subs) {
        for (const rung of RUNGS) {
          out.push({
            skill, sub_skill: code, sub_skill_name: name, rung,
            format: FORMATS[skill][rung - 1], standard,
            target_difficulty: STANDARD_BASE[standard] + RUNG_OFFSET[rung],
          });
        }
      }
    }
  }
  return out;
}

// ── generate: call the deployed function (or mock) ──────────────────────────
async function callGenerate(spec) {
  if (DRY) {
    const good = Math.random() > 0.12;
    return {
      item: {
        question: `[${spec.sub_skill_name} r${spec.rung}] mock question`,
        options: { A: "correct", B: "wrong1", C: "wrong2", D: "wrong3" },
        correct_answer: "A", answer: "correct", explanation: "because.",
        sub_skill: spec.sub_skill, rung: spec.rung,
      },
      attempts: good ? 1 : 2, qa: [{ attempt: 1, issues: good ? [] : ["fixed"] }],
    };
  }
  const res = await fetch(`${SUPABASE_URL}/functions/v1/generate`, {
    method: "POST",
    headers: { Authorization: `Bearer ${ANON}`, "Content-Type": "application/json" },
    body: JSON.stringify({ ...spec, recent_errors: [] }),
  });
  return res.json();
}

// ── judge: independent rubric scoring (or mock) ─────────────────────────────
async function judge(item, spec) {
  if (DRY) {
    const pass = Math.random() > 0.08;
    return {
      answer_correct: pass, single_correct: pass, on_target_subskill: true,
      on_target_rung: pass, age_appropriate: true, issues: pass ? [] : ["mock issue"],
    };
  }
  const prompt = `You are a strict QA reviewer for a Malaysian primary-school English quiz.
Score this item. Reply ONLY as JSON with boolean fields and an issues array:
{"answer_correct":bool,"single_correct":bool,"on_target_subskill":bool,"on_target_rung":bool,"age_appropriate":bool,"issues":[string]}
- answer_correct: the marked answer is actually correct
- single_correct: exactly one option is correct (true for open items)
- on_target_subskill: it tests "${spec.sub_skill_name}"
- on_target_rung: difficulty/task matches rung ${spec.rung}
- age_appropriate: suitable for a Standard ${spec.standard} child
Item: ${JSON.stringify(item)}`;
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${OPENAI_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: JUDGE_MODEL, temperature: 0,
      response_format: { type: "json_object" },
      messages: [{ role: "user", content: prompt }],
    }),
  });
  const data = await res.json();
  try { return JSON.parse(data.choices[0].message.content); }
  catch { return { issues: ["judge parse error"], answer_correct: false, single_correct: false, on_target_subskill: false, on_target_rung: false, age_appropriate: false }; }
}

const CRITERIA = ["answer_correct", "single_correct", "on_target_subskill", "on_target_rung", "age_appropriate"];
const passed = (v) => CRITERIA.every((c) => v[c] === true);
const pct = (x, n) => (n ? `${((x / n) * 100).toFixed(0)}%` : "—");

// ── one run over the whole sample ───────────────────────────────────────────
async function runOnce(runIdx) {
  const genIssuesOf = (gen) =>
    (gen?.error ? [String(gen.error)] : (gen?.qa ?? []).flatMap((a) => a.issues || [])).join(" | ");
  const sample = buildSample();
  const rows = [];
  for (const spec of sample) {
    const gen = await callGenerate(spec);
    if (!gen || !gen.item) {
      rows.push({ run: runIdx, spec, generated: false, attempts: gen?.attempts ?? 0, verdict: null, pass: false, genIssues: genIssuesOf(gen) });
      continue;
    }
    const verdict = await judge(gen.item, spec);
    rows.push({ run: runIdx, spec, generated: true, attempts: gen.attempts ?? 1, item: gen.item, verdict, pass: passed(verdict), genIssues: genIssuesOf(gen) });
  }
  return rows;
}

function headline(rows) {
  const total = rows.length;
  const genOk = rows.filter((r) => r.generated).length;
  const passes = rows.filter((r) => r.pass).length;
  const firstPass = rows.filter((r) => r.attempts === 1).length;
  const avgAttempts = total ? rows.reduce((s, r) => s + (r.attempts || 0), 0) / total : 0;
  return { total, genOk, passes, firstPass, avgAttempts };
}

// ── run N times, aggregate ──────────────────────────────────────────────────
async function main() {
  const perItem = buildSample().length;
  console.log(`Sample: ${perItem} items/run × ${RUNS} run(s) = ${perItem * RUNS} items`);
  console.log(`~${perItem * RUNS * 2} model calls total${DRY ? " (DRY RUN)" : ""}. Judge: ${DRY ? "MOCK" : JUDGE_MODEL}\n`);

  const allRows = [];
  const perRun = [];
  for (let i = 1; i <= RUNS; i++) {
    process.stdout.write(`Run ${i}/${RUNS}… `);
    const rows = await runOnce(i);
    allRows.push(...rows);
    const h = headline(rows);
    perRun.push(h);
    console.log(`generated ${pct(h.genOk, h.total)}, judge pass ${pct(h.passes, h.total)}, first-pass ${pct(h.firstPass, h.total)}`);
  }

  // Averages across runs
  const avg = (f) => perRun.reduce((s, h) => s + f(h), 0) / perRun.length;
  const meanGen = avg((h) => h.genOk / h.total) * 100;
  const meanPass = avg((h) => h.passes / h.total) * 100;
  const meanFirst = avg((h) => h.firstPass / h.total) * 100;
  const meanAttempts = avg((h) => h.avgAttempts);

  // Pooled breakdowns over all runs
  const by = (keyFn) => {
    const m = {};
    for (const r of allRows) { const k = keyFn(r); (m[k] ??= { n: 0, pass: 0 }).n++; if (r.pass) m[k].pass++; }
    return m;
  };
  const perSkill = by((r) => r.spec.skill);
  const perRung = by((r) => `rung ${r.spec.rung}`);
  const judged = allRows.filter((r) => r.verdict);
  const perCriterion = {};
  for (const c of CRITERIA) perCriterion[c] = judged.filter((r) => r.verdict[c]).length;

  const line = (label, x, n) => `| ${label} | ${x}/${n} | ${pct(x, n)} |`;

  // ── report ──
  let md = `# LexiCore — Generation Quality Evaluation\n\n`;
  md += `Sample: **${perItem}** items/run across ${Object.keys(SUBSKILLS).length} skills × `;
  md += `${Object.values(SUBSKILLS).flat().length} sub-skills × rungs ${RUNGS.join(",")}, `;
  md += `standard(s) ${STANDARDS.join(",")}. **${RUNS}** run(s), **${allRows.length}** items total.\n`;
  md += `Generator: \`generate\` (gpt-4.1-mini + validate/repair). Judge: \`${DRY ? "MOCK" : JUDGE_MODEL}\` (independent).\n\n`;

  md += `## Headline (averaged across ${RUNS} run(s))\n\n`;
  md += `- Generation success: **${meanGen.toFixed(1)}%**\n`;
  md += `- Independent-judge pass (all criteria): **${meanPass.toFixed(1)}%**\n`;
  md += `- First-pass (no repair): **${meanFirst.toFixed(1)}%**; avg attempts **${meanAttempts.toFixed(2)}**\n\n`;

  md += `## Per run\n\n| Run | Generated | Judge pass | First-pass | Avg attempts |\n|---|---|---|---|---|\n`;
  perRun.forEach((h, i) => {
    md += `| ${i + 1} | ${pct(h.genOk, h.total)} | ${pct(h.passes, h.total)} | ${pct(h.firstPass, h.total)} | ${h.avgAttempts.toFixed(2)} |\n`;
  });

  md += `\n## Per criterion (pooled)\n\n| Criterion | Pass | Rate |\n|---|---|---|\n`;
  for (const c of CRITERIA) md += line(c, perCriterion[c], judged.length) + "\n";
  md += `\n## Per skill (pooled)\n\n| Skill | Pass | Rate |\n|---|---|---|\n`;
  for (const [k, v] of Object.entries(perSkill)) md += line(k, v.pass, v.n) + "\n";
  md += `\n## Per rung (pooled)\n\n| Rung | Pass | Rate |\n|---|---|---|\n`;
  for (const [k, v] of Object.entries(perRung)) md += line(k, v.pass, v.n) + "\n";

  const fails = allRows.filter((r) => !r.pass);
  md += `\n## Failures (${fails.length})\n\n`;
  if (fails.length === 0) md += `None across all runs.\n`;
  else {
    md += `| Run | Sub-skill | Rung | Format | Issues |\n|---|---|---|---|---|\n`;
    for (const r of fails) {
      const issues = r.verdict
        ? (r.verdict.issues || []).join("; ")
        : `[generation failed] ${r.genIssues || "no item after retries"}`;
      md += `| ${r.run} | ${r.spec.sub_skill} | ${r.spec.rung} | ${r.spec.format} | ${issues || "failed a criterion"} |\n`;
    }
  }
  writeFileSync("evaluation_results.md", md);

  // CSV (all rows)
  let csv = "run,skill,sub_skill,rung,standard,attempts,pass," + CRITERIA.join(",") + ",judge_issues,gen_issues\n";
  for (const r of allRows) {
    const v = r.verdict || {};
    csv += [r.run, r.spec.skill, r.spec.sub_skill, r.spec.rung, r.spec.standard, r.attempts, r.pass,
      ...CRITERIA.map((c) => v[c] ?? ""), `"${(v.issues || []).join("; ")}"`, `"${(r.genIssues || "").replace(/"/g, "'")}"`].join(",") + "\n";
  }
  writeFileSync("evaluation_results.csv", csv);

  // Hand-check sample (for human/judge agreement rate)
  const judgedItems = allRows.filter((r) => r.item);
  const picks = judgedItems.sort(() => Math.random() - 0.5).slice(0, Math.min(HANDCHECK, judgedItems.length));
  let hc = `# Hand-check sample (${picks.length} items)\n\n`;
  hc += `Read each item, decide yourself whether it is correct/on-target/age-appropriate,\n`;
  hc += `then compare with the judge's verdict. Report the agreement rate in your writeup.\n\n`;
  picks.forEach((r, i) => {
    hc += `## ${i + 1}. ${r.spec.sub_skill} — rung ${r.spec.rung}\n\n`;
    hc += `**Question:** ${r.item.question}\n\n`;
    if (r.item.options) hc += `**Options:** ${JSON.stringify(r.item.options)}\n\n`;
    hc += `**Marked correct:** ${r.item.correct_answer ?? r.item.answer ?? "—"}\n\n`;
    hc += `**Judge verdict:** ${JSON.stringify(r.verdict)}\n\n`;
    hc += `**Your verdict (fill in):** pass / fail — notes: __________\n\n---\n\n`;
  });
  writeFileSync("handcheck_sample.md", hc);

  console.log(`\n=== AVERAGED SUMMARY (${RUNS} run(s)) ===`);
  console.log(`Generation success: ${meanGen.toFixed(1)}%`);
  console.log(`Judge pass:         ${meanPass.toFixed(1)}%`);
  console.log(`First-pass:         ${meanFirst.toFixed(1)}%; avg attempts ${meanAttempts.toFixed(2)}`);
  console.log(`\nWrote evaluation_results.md, evaluation_results.csv, handcheck_sample.md`);
}

main().catch((e) => { console.error(e); process.exit(1); });
