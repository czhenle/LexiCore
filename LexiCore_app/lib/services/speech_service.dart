import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Device text-to-speech, used to SAY an English word aloud.
///
/// This exists for the Vocabulary spelling mode: a spelling question that only
/// shows a picture and a written clue isn't really testing spelling — the
/// student has to hear the word to spell it. Runs on the device's own TTS
/// engine, so there's no API cost, no network round-trip, and it works
/// offline.
///
/// Every method swallows its errors. A device with no TTS engine installed,
/// or a locale with no English voice, should mean "the button does nothing"
/// — never a crash in the middle of a practice session.
class SpeechService {
  SpeechService._();
  static final SpeechService _instance = SpeechService._();
  factory SpeechService() => _instance;

  final _tts = FlutterTts();
  bool _configured = false;

  Future<void> _configure() async {
    if (_configured) return;
    _configured = true;
    try {
      // en-GB to match the British spelling the whole app teaches (colour,
      // favourite) — an en-US voice would pronounce some words in a way that
      // contradicts the spelling we're asking for.
      await _tts.setLanguage('en-GB');
      // Slower than default: these are 7-12 year olds being asked to catch
      // every sound in a word they then have to spell back.
      await _tts.setSpeechRate(0.4);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
    } catch (e) {
      debugPrint('TTS configuration failed: $e');
    }
  }

  /// Speaks [text] aloud. Safe to call repeatedly — a child re-listening to a
  /// word several times is expected, so any in-progress speech is stopped
  /// first rather than queued behind it.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _configure();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS speak failed: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('TTS stop failed: $e');
    }
  }
}
