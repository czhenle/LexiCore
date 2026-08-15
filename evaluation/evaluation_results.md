# LexiCore — Generation Quality Evaluation

Sample: **36** items/run across 4 skills × 12 sub-skills × rungs 1,3,4, standard(s) 3. **3** run(s), **108** items total.
Generator: `generate` (gpt-4.1-mini + validate/repair). Judge: `gpt-4.1` (independent).

## Headline (averaged across 3 run(s))

- Generation success: **33.3%**
- Independent-judge pass (all criteria): **32.4%**
- First-pass (no repair): **14.8%**; avg attempts **2.40**

## Per run

| Run | Generated | Judge pass | First-pass | Avg attempts |
|---|---|---|---|---|
| 1 | 25% | 22% | 14% | 2.33 |
| 2 | 39% | 39% | 14% | 2.47 |
| 3 | 36% | 36% | 17% | 2.39 |

## Per criterion (pooled)

| Criterion | Pass | Rate |
|---|---|---|
| answer_correct | 36/36 | 100% |
| single_correct | 35/36 | 97% |
| on_target_subskill | 36/36 | 100% |
| on_target_rung | 36/36 | 100% |
| age_appropriate | 36/36 | 100% |

## Per skill (pooled)

| Skill | Pass | Rate |
|---|---|---|
| Vocabulary | 9/27 | 33% |
| Grammar | 13/27 | 48% |
| Reading | 8/27 | 30% |
| Writing | 5/27 | 19% |

## Per rung (pooled)

| Rung | Pass | Rate |
|---|---|---|
| rung 1 | 20/36 | 56% |
| rung 3 | 6/36 | 17% |
| rung 4 | 9/36 | 25% |

## Failures (73)

| Run | Sub-skill | Rung | Format | Issues |
|---|---|---|---|---|
| 1 | vocab.food_drink | 3 | cloze_sentence_wordbank | [generation failed] item.answer.trim is not a function |
| 1 | vocab.food_drink | 4 | cloze_paragraph_open | [generation failed] no valid item produced |
| 1 | vocab.animals_nature | 3 | cloze_sentence_wordbank | [generation failed] item.answer.trim is not a function |
| 1 | vocab.animals_nature | 4 | cloze_paragraph_open | [generation failed] no valid item produced |
| 1 | vocab.feelings | 3 | cloze_sentence_wordbank | [generation failed] no valid item produced |
| 1 | vocab.feelings | 4 | cloze_paragraph_open | [generation failed] no valid item produced |
| 1 | grammar.past_tense | 4 | transform_or_reorder | [generation failed] no valid item produced |
| 1 | grammar.articles | 3 | gap_fill | [generation failed] no valid item produced |
| 1 | grammar.articles | 4 | transform_or_reorder | [generation failed] no valid item produced |
| 1 | grammar.sva | 1 | worked_example | [generation failed] no valid item produced |
| 1 | grammar.sva | 3 | gap_fill | [generation failed] no valid item produced |
| 1 | grammar.sva | 4 | transform_or_reorder | [generation failed] no valid item produced |
| 1 | reading.literal | 1 | vocab_preview | [generation failed] no valid item produced |
| 1 | reading.literal | 3 | sequence_order | [generation failed] item.answer.trim is not a function |
| 1 | reading.literal | 4 | mcq_inference | [generation failed] no valid item produced |
| 1 | reading.inference | 1 | vocab_preview | [generation failed] no valid item produced |
| 1 | reading.inference | 3 | sequence_order | [generation failed] no valid item produced |
| 1 | reading.inference | 4 | mcq_inference | Option D ('Ali wants to keep the sun away.') is also a plausible inference, making more than one answer potentially correct. |
| 1 | reading.sequencing | 3 | sequence_order | [generation failed] item.answer.trim is not a function |
| 1 | writing.mechanics | 1 | punctuation_fix | [generation failed] no valid item produced |
| 1 | writing.mechanics | 3 | sentence_combine | [generation failed] no valid item produced |
| 1 | writing.mechanics | 4 | guided_composition | [generation failed] no valid item produced |
| 1 | writing.sentence_combining | 1 | punctuation_fix | [generation failed] no valid item produced |
| 1 | writing.sentence_combining | 3 | sentence_combine | [generation failed] no valid item produced |
| 1 | writing.sentence_combining | 4 | guided_composition | [generation failed] no valid item produced |
| 1 | writing.spelling | 1 | punctuation_fix | [generation failed] no valid item produced |
| 1 | writing.spelling | 3 | sentence_combine | [generation failed] no valid item produced |
| 1 | writing.spelling | 4 | guided_composition | [generation failed] no valid item produced |
| 2 | vocab.food_drink | 3 | cloze_sentence_wordbank | [generation failed] no valid item produced |
| 2 | vocab.food_drink | 4 | cloze_paragraph_open | [generation failed] no valid item produced |
| 2 | vocab.animals_nature | 3 | cloze_sentence_wordbank | [generation failed] no valid item produced |
| 2 | vocab.animals_nature | 4 | cloze_paragraph_open | [generation failed] no valid item produced |
| 2 | vocab.feelings | 3 | cloze_sentence_wordbank | [generation failed] no valid item produced |
| 2 | vocab.feelings | 4 | cloze_paragraph_open | [generation failed] no valid item produced |
| 2 | grammar.past_tense | 4 | transform_or_reorder | [generation failed] no valid item produced |
| 2 | grammar.articles | 4 | transform_or_reorder | [generation failed] no valid item produced |
| 2 | grammar.sva | 1 | worked_example | [generation failed] no valid item produced |
| 2 | grammar.sva | 4 | transform_or_reorder | [generation failed] no valid item produced |
| 2 | reading.literal | 1 | vocab_preview | [generation failed] no valid item produced |
| 2 | reading.literal | 3 | sequence_order | [generation failed] no valid item produced |
| 2 | reading.literal | 4 | mcq_inference | [generation failed] no valid item produced |
| 2 | reading.inference | 1 | vocab_preview | [generation failed] no valid item produced |
| 2 | reading.inference | 3 | sequence_order | [generation failed] no valid item produced |
| 2 | reading.sequencing | 3 | sequence_order | [generation failed] item.answer.trim is not a function |
| 2 | writing.mechanics | 1 | punctuation_fix | [generation failed] no valid item produced |
| 2 | writing.mechanics | 3 | sentence_combine | [generation failed] no valid item produced |
| 2 | writing.mechanics | 4 | guided_composition | [generation failed] no valid item produced |
| 2 | writing.sentence_combining | 3 | sentence_combine | [generation failed] no valid item produced |
| 2 | writing.spelling | 3 | sentence_combine | [generation failed] no valid item produced |
| 2 | writing.spelling | 4 | guided_composition | [generation failed] no valid item produced |
| 3 | vocab.food_drink | 3 | cloze_sentence_wordbank | [generation failed] item.answer.trim is not a function |
| 3 | vocab.food_drink | 4 | cloze_paragraph_open | [generation failed] no valid item produced |
| 3 | vocab.animals_nature | 3 | cloze_sentence_wordbank | [generation failed] no valid item produced |
| 3 | vocab.animals_nature | 4 | cloze_paragraph_open | [generation failed] no valid item produced |
| 3 | vocab.feelings | 3 | cloze_sentence_wordbank | [generation failed] no valid item produced |
| 3 | vocab.feelings | 4 | cloze_paragraph_open | [generation failed] no valid item produced |
| 3 | grammar.past_tense | 4 | transform_or_reorder | [generation failed] no valid item produced |
| 3 | grammar.sva | 1 | worked_example | [generation failed] no valid item produced |
| 3 | grammar.sva | 3 | gap_fill | [generation failed] no valid item produced |
| 3 | grammar.sva | 4 | transform_or_reorder | [generation failed] no valid item produced |
| 3 | reading.literal | 1 | vocab_preview | [generation failed] no valid item produced |
| 3 | reading.literal | 3 | sequence_order | [generation failed] item.answer.trim is not a function |
| 3 | reading.literal | 4 | mcq_inference | [generation failed] no valid item produced |
| 3 | reading.inference | 3 | sequence_order | [generation failed] no valid item produced |
| 3 | reading.sequencing | 1 | vocab_preview | [generation failed] no valid item produced |
| 3 | reading.sequencing | 3 | sequence_order | [generation failed] no valid item produced |
| 3 | writing.mechanics | 1 | punctuation_fix | [generation failed] no valid item produced |
| 3 | writing.mechanics | 3 | sentence_combine | [generation failed] no valid item produced |
| 3 | writing.mechanics | 4 | guided_composition | [generation failed] no valid item produced |
| 3 | writing.sentence_combining | 1 | punctuation_fix | [generation failed] no valid item produced |
| 3 | writing.sentence_combining | 3 | sentence_combine | [generation failed] no valid item produced |
| 3 | writing.spelling | 1 | punctuation_fix | [generation failed] no valid item produced |
| 3 | writing.spelling | 3 | sentence_combine | [generation failed] no valid item produced |
