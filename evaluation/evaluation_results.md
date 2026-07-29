# LexiCore — Generation Quality Evaluation

Sample: **60** items/run across 4 skills × 12 sub-skills × rungs 1,2,3,4,5, standard(s) 3. **3** run(s), **180** items total.
Generator: `generate` (gpt-4.1-mini + validate/repair). Judge: `gpt-4.1` (independent).

## Headline (averaged across 3 run(s))

- Generation success: **53.9%**
- Independent-judge pass (all criteria): **52.8%**
- First-pass (no repair): **35.0%**; avg attempts **2.03**

## Per run

| Run | Generated | Judge pass | First-pass | Avg attempts |
|---|---|---|---|---|
| 1 | 53% | 53% | 40% | 1.97 |
| 2 | 50% | 50% | 33% | 2.05 |
| 3 | 58% | 55% | 32% | 2.07 |

## Per criterion (pooled)

| Criterion | Pass | Rate |
|---|---|---|
| answer_correct | 96/97 | 99% |
| single_correct | 97/97 | 100% |
| on_target_subskill | 97/97 | 100% |
| on_target_rung | 96/97 | 99% |
| age_appropriate | 97/97 | 100% |

## Per skill (pooled)

| Skill | Pass | Rate |
|---|---|---|
| Vocabulary | 26/45 | 58% |
| Grammar | 26/45 | 58% |
| Reading | 26/45 | 58% |
| Writing | 17/45 | 38% |

## Per rung (pooled)

| Rung | Pass | Rate |
|---|---|---|
| rung 1 | 20/36 | 56% |
| rung 2 | 33/36 | 92% |
| rung 3 | 4/36 | 11% |
| rung 4 | 9/36 | 25% |
| rung 5 | 29/36 | 81% |

## Failures (85)

| Run | Sub-skill | Rung | Issues |
|---|---|---|---|
| 1 | vocab.food_drink | 3 | no item generated |
| 1 | vocab.food_drink | 4 | no item generated |
| 1 | vocab.animals_nature | 3 | no item generated |
| 1 | vocab.animals_nature | 4 | no item generated |
| 1 | vocab.feelings | 4 | no item generated |
| 1 | grammar.past_tense | 4 | no item generated |
| 1 | grammar.articles | 3 | no item generated |
| 1 | grammar.articles | 4 | no item generated |
| 1 | grammar.articles | 5 | no item generated |
| 1 | grammar.sva | 3 | no item generated |
| 1 | grammar.sva | 4 | no item generated |
| 1 | grammar.sva | 5 | no item generated |
| 1 | reading.literal | 1 | no item generated |
| 1 | reading.literal | 3 | no item generated |
| 1 | reading.literal | 4 | no item generated |
| 1 | reading.inference | 1 | no item generated |
| 1 | reading.inference | 3 | no item generated |
| 1 | reading.sequencing | 1 | no item generated |
| 1 | reading.sequencing | 3 | no item generated |
| 1 | writing.mechanics | 1 | no item generated |
| 1 | writing.mechanics | 2 | no item generated |
| 1 | writing.mechanics | 3 | no item generated |
| 1 | writing.mechanics | 4 | no item generated |
| 1 | writing.sentence_combining | 1 | no item generated |
| 1 | writing.sentence_combining | 3 | no item generated |
| 1 | writing.spelling | 1 | no item generated |
| 1 | writing.spelling | 3 | no item generated |
| 1 | writing.spelling | 4 | no item generated |
| 2 | vocab.food_drink | 3 | no item generated |
| 2 | vocab.food_drink | 4 | no item generated |
| 2 | vocab.food_drink | 5 | no item generated |
| 2 | vocab.animals_nature | 3 | no item generated |
| 2 | vocab.animals_nature | 4 | no item generated |
| 2 | vocab.feelings | 3 | no item generated |
| 2 | vocab.feelings | 4 | no item generated |
| 2 | vocab.feelings | 5 | no item generated |
| 2 | grammar.past_tense | 4 | no item generated |
| 2 | grammar.articles | 3 | no item generated |
| 2 | grammar.articles | 4 | no item generated |
| 2 | grammar.sva | 1 | no item generated |
| 2 | grammar.sva | 3 | no item generated |
| 2 | grammar.sva | 4 | no item generated |
| 2 | reading.literal | 1 | no item generated |
| 2 | reading.literal | 3 | no item generated |
| 2 | reading.literal | 4 | no item generated |
| 2 | reading.inference | 1 | no item generated |
| 2 | reading.inference | 3 | no item generated |
| 2 | reading.sequencing | 3 | no item generated |
| 2 | writing.mechanics | 1 | no item generated |
| 2 | writing.mechanics | 2 | no item generated |
| 2 | writing.mechanics | 3 | no item generated |
| 2 | writing.mechanics | 5 | no item generated |
| 2 | writing.sentence_combining | 3 | no item generated |
| 2 | writing.sentence_combining | 4 | no item generated |
| 2 | writing.spelling | 1 | no item generated |
| 2 | writing.spelling | 3 | no item generated |
| 2 | writing.spelling | 4 | no item generated |
| 2 | writing.spelling | 5 | no item generated |
| 3 | vocab.food_drink | 3 | no item generated |
| 3 | vocab.food_drink | 4 | no item generated |
| 3 | vocab.animals_nature | 3 | no item generated |
| 3 | vocab.animals_nature | 4 | no item generated |
| 3 | vocab.feelings | 3 | no item generated |
| 3 | vocab.feelings | 4 | no item generated |
| 3 | grammar.past_tense | 1 | The answer changes 'Today' to 'Yesterday', which was not required. The instruction only asked to change the verb to past tense, so the correct answer should be 'Today, Ali played football.' |
| 3 | grammar.past_tense | 4 | no item generated |
| 3 | grammar.articles | 3 | no item generated |
| 3 | grammar.articles | 4 | no item generated |
| 3 | grammar.sva | 3 | no item generated |
| 3 | grammar.sva | 4 | no item generated |
| 3 | reading.literal | 1 | no item generated |
| 3 | reading.literal | 3 | no item generated |
| 3 | reading.literal | 4 | no item generated |
| 3 | reading.inference | 3 | no item generated |
| 3 | reading.sequencing | 1 | no item generated |
| 3 | reading.sequencing | 3 | no item generated |
| 3 | writing.mechanics | 1 | no item generated |
| 3 | writing.mechanics | 2 | no item generated |
| 3 | writing.mechanics | 3 | no item generated |
| 3 | writing.mechanics | 4 | no item generated |
| 3 | writing.mechanics | 5 | no item generated |
| 3 | writing.sentence_combining | 3 | no item generated |
| 3 | writing.spelling | 1 | no item generated |
| 3 | writing.spelling | 3 | no item generated |
| 3 | writing.spelling | 4 | Task is more composition-focused and assesses multiple skills (sentence construction, vocabulary, coherence) in addition to spelling.; Rung 4 for spelling typically involves spelling words in isolation or within short sentences, not extended writing or paragraph composition. |
