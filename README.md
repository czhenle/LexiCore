# LexiCore 📚

An AI-powered personalised English learning assistant for Malaysian primary school students (Standard 1–6), built with Flutter and Supabase. LexiCore delivers adaptive vocabulary, grammar, reading, and writing exercises generated on-demand by GPT-4o-mini, with a built-in AI tutor, a personalised 4-week study schedule, and a KSSR-aligned curriculum progression system.

---

## 📋 Table of Contents

- [🏪 About](#-about)
- [✨ Features](#-features)
- [🏗️ System Architecture](#️-system-architecture)
- [📱 Screens](#-screens)
- [📁 Project Structure](#-project-structure)
- [🗄️ Database Schema](#️-database-schema)
- [🚀 Getting Started](#-getting-started)
- [🛠️ Technologies Used](#️-technologies-used)
- [📦 Dependencies](#-dependencies)
- [📜 License](#-license)

---

## 🏪 About

LexiCore is a Flutter mobile application designed to personalise English learning for Malaysian primary school students following the KSSR syllabus. Upon registration, students complete an initial diagnostic assessment that determines their detected ability level across four skill domains — Vocabulary, Grammar, Reading, and Writing. All learning content is generated dynamically using AI via Supabase Edge Functions, meaning every exercise session is unique and calibrated to the student's current level and weaknesses. Progress is tracked in Supabase's PostgreSQL database and used to unlock the next curriculum unit, adapt the AI chatbot's responses, and refine the personalised study schedule.

---

## ✨ Features

- 🎯 **Initial Assessment** — Diagnostic quiz across all four skills on first login to determine the student's ability level and establish baseline scores
- 📈 **Adaptive Level Detection** — Detected level is calculated from average assessment score and adjusts the student one standard up or down from their declared school standard
- 📖 **Vocabulary Module** — Three question modes: image-based (DALL-E 2 illustrations), definition-matching, and fill-in-the-blank context sentences
- ✏️ **Grammar Module** — Level-calibrated MCQs with difficulty profiles (sentence length, question type, distractor hardness) mapped to Standard 1–6
- 📰 **Reading Module** — AI-generated articles with five comprehension questions including inference-type items
- 🖊️ **Writing Module** — Four exercise types: sentence completion, word ordering, error correction, and guided composition
- 🗓️ **AI Study Schedule** — Personalised 4-week study plan generated from the student's skill scores, weaknesses, and available daily study time, with adjustable modifiers (more/less/shorten/lengthen)
- 🤖 **Lexi AI Chatbot** — Conversational English tutor with student profile awareness, intent inference, and gentle grammar correction
- 📰 **Article Feed** — Home screen article reader with AI-generated level-appropriate reading material and vocabulary hints
- 🔒 **Unit Progression** — KSSR-aligned curriculum with 6 units per module; units unlock based on prerequisite score thresholds
- 👤 **Student Profiling** — Onboarding collects name, age, school standard, and daily study time; profile saved to Supabase
- 📊 **Quiz History** — All completed quiz sessions stored in Supabase with scores and timestamps

---

## 🏗️ System Architecture

LexiCore uses a three-layer architecture:

**Layer 1 — Flutter Frontend**
The mobile app handles all UI, navigation, and state. It communicates with two backends: Supabase Auth + Database for user data, and Supabase Edge Functions for AI content generation.

**Layer 2 — Supabase Edge Functions (AI Backend)**
Seven Deno-based serverless functions deployed to Supabase, each implementing a dedicated AI generation chain using OpenAI GPT-4o-mini (via direct API or LangChain) and returning structured JSON:

| Function | Description |
|----------|-------------|
| `article` | Generates level-adaptive reading articles with vocabulary hints |
| `vocabulary` | Generates MCQs in image, meaning, or context mode |
| `grammar` | Generates difficulty-calibrated grammar MCQs with Zod schema validation |
| `reading` | Generates a reading passage with five comprehension questions |
| `writing` | Generates writing exercises across four exercise types |
| `chatbot` | Powers the Lexi AI tutor with student profile context |
| `schedule` | Generates a personalised 4-week study plan with modifier support |

**Layer 3 — Supabase PostgreSQL Database**
Stores student profiles, assessment results, quiz progress history, and saved study schedules. Row-level security ensures each user only accesses their own data.

---

## 📱 Screens

| Screen | File | Description |
|--------|------|-------------|
| Splash | `splash_screen.dart` | Animated launch screen |
| Landing | `landing_screen.dart` | Welcome screen with login and register entry points |
| Login | `login_screen.dart` | Supabase email/password authentication |
| Register | `registration_screen.dart` | New account creation |
| Onboarding Profile | `onboarding_profile_screen.dart` | Collects name, age, standard, and study time |
| Initial Assessment | `initial_assessment_screen.dart` | Diagnostic quiz across all four skills |
| Home | `home_screen.dart` | Dashboard with AI article feed and today's task |
| Article | `article_screen.dart` | Full article reader with vocabulary hints |
| Module Selection | `module_selection_screen.dart` | Choose a skill module (Vocabulary, Grammar, Reading, Writing) |
| Standard Selection | `standard_selection_screen.dart` | Pick a school standard for free-play module access |
| Vocabulary Module | `vocabulary_module_screen.dart` | Vocabulary exercise with mode selection |
| Grammar Module | `grammar_module_screen.dart` | Grammar topic and unit selection |
| Reading Module | `reading_module_screen.dart` | Reading passage with comprehension questions |
| Writing Module | `writing_module_screen.dart` | Writing exercise type selection and questions |
| Module Quiz | `module_quiz_screen.dart` | Shared quiz screen for all module types |
| Result | `result_screen.dart` | Score breakdown and performance feedback after each quiz |
| Study Schedule | `study_schedule_screen.dart` | AI-generated 4-week plan with week/day breakdown and modifier controls |
| AI Chatbot | `ai_chatbot_screen.dart` | Conversational chat interface with Lexi the AI tutor |
| User Profile | `user_profile_screen.dart` | Account details, skill scores, level, and logout |

---

## 📁 Project Structure

```
LexiCore/
└── LexiCore_app/
    ├── assets/
    │   └── icon_image.png                  # App launcher icon
    ├── lib/
    │   ├── main.dart                        # App entry, Supabase initialisation, MaterialApp
    │   ├── data/
    │   │   └── curriculum.dart              # KSSR curriculum units, topics, prerequisite scores
    │   ├── screens/
    │   │   ├── initialization/
    │   │   │   ├── splash_screen.dart
    │   │   │   └── landing_screen.dart
    │   │   ├── login_and_registration/
    │   │   │   ├── login_screen.dart
    │   │   │   └── registration_screen.dart
    │   │   ├── user_profiling/
    │   │   │   ├── onboarding_profile_screen.dart
    │   │   │   ├── initial_assessment_screen.dart
    │   │   │   └── user_profile_screen.dart
    │   │   ├── home/
    │   │   │   ├── home_screen.dart
    │   │   │   └── article_screen.dart
    │   │   ├── modules/
    │   │   │   ├── module_selection_screen.dart
    │   │   │   ├── standard_selection_screen.dart
    │   │   │   ├── vocabulary_module_screen.dart
    │   │   │   ├── grammar_module_screen.dart
    │   │   │   ├── reading_module_screen.dart
    │   │   │   ├── writing_module_screen.dart
    │   │   │   ├── module_quiz_screen.dart
    │   │   │   └── result_screen.dart
    │   │   ├── ai_chatbot/
    │   │   │   └── ai_chatbot_screen.dart
    │   │   └── ai_schedule/
    │   │       └── study_schedule_screen.dart
    │   ├── services/
    │   │   ├── api_service.dart             # HTTP calls to all 7 Supabase Edge Functions
    │   │   ├── supabase_service.dart        # Auth, student profile, assessment, quiz progress, schedule
    │   │   └── storage_service.dart         # Local secure storage for session and profile cache
    │   └── widgets/
    │       └── lexi_nav_bar.dart            # Shared bottom navigation bar
    ├── pubspec.yaml
    └── analysis_options.yaml
```

---

## 🗄️ Database Schema

The following tables are used in Supabase PostgreSQL:

| Table | Description |
|-------|-------------|
| `student_profiles` | Stores username, age, school standard, and study time per user |
| `assessment_results` | Stores vocabulary, grammar, reading, writing scores and detected level |
| `quiz_progress` | Records every completed quiz with module type, unit, topic, score, and timestamp |
| `study_schedules` | Stores the full AI-generated 4-week plan JSON per user |

---

## 🚀 Getting Started

### 🔧 Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart SDK `^3.11.1`)
- A [Supabase](https://supabase.com) project with the tables above created
- Android Studio or Xcode for running on a device or emulator
- Android 5.0+ or iOS 12+

### 💻 Running Locally

1. Clone the repository:
   ```bash
   git clone https://github.com/czhenle/LexiCore.git
   cd LexiCore/LexiCore_app
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   flutter run
   ```

4. Build a release APK:
   ```bash
   flutter build apk --release
   ```

### ⚙️ Environment Configuration

The Supabase URL and anon key are configured in `lib/main.dart` and `lib/services/api_service.dart`. Replace the values with your own Supabase project credentials before deploying:

```dart
await Supabase.initialize(
  url: 'YOUR_SUPABASE_URL',
  anonKey: 'YOUR_SUPABASE_ANON_KEY',
);
```

---

## 🛠️ Technologies Used

| Technology | Purpose |
|------------|---------|
| Flutter | Cross-platform mobile UI framework |
| Dart | Application logic and state management |
| Supabase | Authentication, PostgreSQL database, and Edge Function hosting |
| OpenAI GPT-4o-mini | AI content generation across all 7 modules |
| LangChain (Deno) | Structured output and prompt chaining for grammar and vocabulary modules |
| DALL-E 2 | Image generation for vocabulary image mode |
| Deno | Supabase Edge Function runtime |

---

## 📦 Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `supabase_flutter` | ^2.5.0 | Supabase Auth and database client |
| `http` | ^1.6.0 | HTTP calls to Supabase Edge Functions |
| `flutter_secure_storage` | ^10.0.0 | Local secure session and profile caching |
| `image_picker` | ^1.2.1 | Profile picture selection from camera or gallery |
| `cupertino_icons` | ^1.0.8 | iOS-style icon support |
| `flutter_launcher_icons` | ^0.13.1 | Custom app launcher icon generation |

---

## 📜 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
