# LexiCore — Generation Quality Evaluation

Sample: **60** items/run across 4 skills × 12 sub-skills × rungs 1,2,3,4,5, standard(s) 3. **3** run(s), **180** items total.
Generator: `generate` (gpt-4.1-mini + validate/repair). Judge: `MOCK` (independent).

## Headline (averaged across 3 run(s))

- Generation success: **100.0%**
- Independent-judge pass (all criteria): **86.1%**
- First-pass (no repair): **87.2%**; avg attempts **1.13**

## Per run

| Run | Generated | Judge pass | First-pass | Avg attempts |
|---|---|---|---|---|
| 1 | 100% | 83% | 88% | 1.12 |
| 2 | 100% | 88% | 85% | 1.15 |
| 3 | 100% | 87% | 88% | 1.12 |

## Per criterion (pooled)

| Criterion | Pass | Rate |
|---|---|---|
| answer_correct | 155/180 | 86% |
| single_correct | 155/180 | 86% |
| on_target_subskill | 180/180 | 100% |
| on_target_rung | 155/180 | 86% |
| age_appropriate | 180/180 | 100% |

## Per skill (pooled)

| Skill | Pass | Rate |
|---|---|---|
| Vocabulary | 38/45 | 84% |
| Grammar | 39/45 | 87% |
| Reading | 41/45 | 91% |
| Writing | 37/45 | 82% |

## Per rung (pooled)

| Rung | Pass | Rate |
|---|---|---|
| rung 1 | 30/36 | 83% |
| rung 2 | 33/36 | 92% |
| rung 3 | 29/36 | 81% |
| rung 4 | 31/36 | 86% |
| rung 5 | 32/36 | 89% |

## Failures (25)

| Run | Sub-skill | Rung | Issues |
|---|---|---|---|
| 1 | vocab.food_drink | 5 | mock issue |
| 1 | vocab.feelings | 1 | mock issue |
| 1 | vocab.feelings | 3 | mock issue |
| 1 | grammar.past_tense | 2 | mock issue |
| 1 | grammar.articles | 3 | mock issue |
| 1 | grammar.articles | 4 | mock issue |
| 1 | reading.literal | 2 | mock issue |
| 1 | writing.mechanics | 1 | mock issue |
| 1 | writing.sentence_combining | 3 | mock issue |
| 1 | writing.spelling | 5 | mock issue |
| 2 | vocab.food_drink | 3 | mock issue |
| 2 | vocab.animals_nature | 4 | mock issue |
| 2 | vocab.feelings | 1 | mock issue |
| 2 | reading.literal | 3 | mock issue |
| 2 | reading.sequencing | 1 | mock issue |
| 2 | writing.mechanics | 2 | mock issue |
| 2 | writing.sentence_combining | 5 | mock issue |
| 3 | vocab.food_drink | 4 | mock issue |
| 3 | grammar.past_tense | 1 | mock issue |
| 3 | grammar.sva | 3 | mock issue |
| 3 | grammar.sva | 4 | mock issue |
| 3 | reading.literal | 4 | mock issue |
| 3 | writing.mechanics | 1 | mock issue |
| 3 | writing.sentence_combining | 3 | mock issue |
| 3 | writing.spelling | 5 | mock issue |
