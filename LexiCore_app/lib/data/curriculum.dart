class CurriculumUnit {
  final int unitNumber;
  final String topic;
  final String description;
  final int prerequisiteScore; // minimum % needed on previous unit to unlock

  const CurriculumUnit({
    required this.unitNumber,
    required this.topic,
    required this.description,
    required this.prerequisiteScore,
  });
}

class Curriculum {
  static const Map<String, List<CurriculumUnit>> units = {
    'Vocabulary': [
      CurriculumUnit(
        unitNumber: 1,
        topic: 'People and Family',
        description: 'Names for family members and describing people',
        prerequisiteScore: 0,
      ),
      CurriculumUnit(
        unitNumber: 2,
        topic: 'Animals and Nature',
        description: 'Common animals, plants, and the natural world',
        prerequisiteScore: 50,
      ),
      CurriculumUnit(
        unitNumber: 3,
        topic: 'Food and Drink',
        description: 'Words for meals, ingredients, and eating',
        prerequisiteScore: 50,
      ),
      CurriculumUnit(
        unitNumber: 4,
        topic: 'School and Learning',
        description: 'Classroom objects, subjects, and school activities',
        prerequisiteScore: 60,
      ),
      CurriculumUnit(
        unitNumber: 5,
        topic: 'Community and Places',
        description: 'Buildings, jobs, and places in the community',
        prerequisiteScore: 60,
      ),
      CurriculumUnit(
        unitNumber: 6,
        topic: 'Feelings and Emotions',
        description: 'Words to describe how we feel',
        prerequisiteScore: 70,
      ),
    ],

    'Grammar': [
      CurriculumUnit(
        unitNumber: 1,
        topic: 'Simple Sentences',
        description: 'Subject + verb + object sentence structure',
        prerequisiteScore: 0,
      ),
      CurriculumUnit(
        unitNumber: 2,
        topic: 'Nouns and Pronouns',
        description: 'Common/proper nouns, personal pronouns I/you/he/she',
        prerequisiteScore: 50,
      ),
      CurriculumUnit(
        unitNumber: 3,
        topic: 'Present Tense',
        description: 'Simple present and present continuous tense',
        prerequisiteScore: 50,
      ),
      CurriculumUnit(
        unitNumber: 4,
        topic: 'Past Tense',
        description: 'Simple past tense with regular and irregular verbs',
        prerequisiteScore: 60,
      ),
      CurriculumUnit(
        unitNumber: 5,
        topic: 'Adjectives and Adverbs',
        description: 'Describing words and how they modify sentences',
        prerequisiteScore: 60,
      ),
      CurriculumUnit(
        unitNumber: 6,
        topic: 'Prepositions and Conjunctions',
        description: 'Linking words and positional language',
        prerequisiteScore: 70,
      ),
    ],

    'Reading': [
      CurriculumUnit(
        unitNumber: 1,
        topic: 'Short Descriptions',
        description: 'Reading simple sentences about people and objects',
        prerequisiteScore: 0,
      ),
      CurriculumUnit(
        unitNumber: 2,
        topic: 'Simple Stories',
        description: 'Short narratives with a beginning, middle, and end',
        prerequisiteScore: 50,
      ),
      CurriculumUnit(
        unitNumber: 3,
        topic: 'Informational Texts',
        description: 'Reading simple facts and non-fiction passages',
        prerequisiteScore: 50,
      ),
      CurriculumUnit(
        unitNumber: 4,
        topic: 'Dialogues and Conversations',
        description: 'Understanding conversations between characters',
        prerequisiteScore: 60,
      ),
      CurriculumUnit(
        unitNumber: 5,
        topic: 'Instructions and Procedures',
        description: 'Following step-by-step written instructions',
        prerequisiteScore: 60,
      ),
      CurriculumUnit(
        unitNumber: 6,
        topic: 'Longer Passages',
        description: 'Reading and understanding multi-paragraph texts',
        prerequisiteScore: 70,
      ),
    ],

    'Writing': [
      CurriculumUnit(
        unitNumber: 1,
        topic: 'Copying and Tracing Words',
        description: 'Forming letters and copying simple words correctly',
        prerequisiteScore: 0,
      ),
      CurriculumUnit(
        unitNumber: 2,
        topic: 'Completing Sentences',
        description: 'Filling in blanks to complete simple sentences',
        prerequisiteScore: 50,
      ),
      CurriculumUnit(
        unitNumber: 3,
        topic: 'Describing a Picture',
        description: 'Writing 2–3 sentences about an image',
        prerequisiteScore: 50,
      ),
      CurriculumUnit(
        unitNumber: 4,
        topic: 'Simple Paragraphs',
        description: 'Writing a short paragraph on a familiar topic',
        prerequisiteScore: 60,
      ),
      CurriculumUnit(
        unitNumber: 5,
        topic: 'Short Stories',
        description: 'Writing a simple narrative with a clear sequence',
        prerequisiteScore: 60,
      ),
      CurriculumUnit(
        unitNumber: 6,
        topic: 'Structured Essays',
        description: 'Writing with an introduction, body, and conclusion',
        prerequisiteScore: 70,
      ),
    ],
  };

  /// Returns the next unit a student should study for a given module,
  /// based on their highest completed unit and its score.
  static CurriculumUnit getNextUnit(
      String moduleType, int highestCompletedUnit, int lastScore) {
    final moduleUnits = units[moduleType] ?? [];
    if (moduleUnits.isEmpty) return _fallback(moduleType);

    // If no units completed yet, start at unit 1
    if (highestCompletedUnit == 0) return moduleUnits.first;

    // Find the next unit — unlock it if they scored above the threshold
    final nextIndex = highestCompletedUnit; // units are 1-indexed
    if (nextIndex >= moduleUnits.length) {
      // Completed all units — return the last one for review
      return moduleUnits.last;
    }

    final nextUnit = moduleUnits[nextIndex];
    if (lastScore >= nextUnit.prerequisiteScore) {
      return nextUnit;
    }

    // Score too low — repeat the current unit
    return moduleUnits[highestCompletedUnit - 1];
  }

  static CurriculumUnit _fallback(String moduleType) {
    return CurriculumUnit(
      unitNumber: 1,
      topic: 'Introduction',
      description: 'Getting started with $moduleType',
      prerequisiteScore: 0,
    );
  }
}