import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Runs on-device text recognition on a photo of an Engineering Department
/// tag and tries to pull out the Part No, Description, and Location fields.
///
/// Printed field labels (PART NO, DESCRIPTION, LOCATION...) recognize
/// reliably. Handwritten entries next to them are best-effort only —
/// the caller should always let the user review/correct before saving.
/// Raw recognized text is always returned so mismatches can be diagnosed.
class OcrUtil {
  static Future<Map<String, String>> extractTagFields(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final result = await recognizer.processImage(inputImage);

      final lines = result.text
          .split('\n')
          .map((l) => _cleanLine(l))
          .where((l) => l.isNotEmpty)
          .toList();

      String findAfter(List<String> keys) {
        for (int i = 0; i < lines.length; i++) {
          final upper = lines[i].toUpperCase();
          for (final k in keys) {
            final idx = upper.indexOf(k);
            if (idx == -1) continue;
            // Everything right after the label - e.g. for "PART NO: ABC123"
            // this starts as ": ABC123". Strip the separator punctuation
            // (colon/dot/dash) the label leaves behind, not just whitespace,
            // or the value ends up polluted with a leading ":" that was
            // never meant to be part of it.
            final rest = _stripLeadingPunctuation(lines[i].substring(idx + k.length));
            if (rest.isNotEmpty) return rest;
            if (i + 1 < lines.length) return _stripLeadingPunctuation(lines[i + 1]);
          }
        }
        return '';
      }

      return {
        'partNo': findAfter(['PART NO', 'PARTNO', 'P/N']),
        'description': findAfter(['DESCRIPTION', 'DESC']),
        'location': findAfter(['LOCATION', 'LOC.']),
        'rawText': result.text,
      };
    } catch (e) {
      return {
        'partNo': '',
        'description': '',
        'location': '',
        'rawText': '',
        'error': e.toString(),
      };
    } finally {
      await recognizer.close();
    }
  }

  /// Strips leading dotted/underscore placeholder lines (e.g. "PART NO.....")
  /// down to just the label + colon, and removes stray dot leaders anywhere.
  static String _cleanLine(String line) {
    var cleaned = line.replaceAll(RegExp(r'\.{2,}'), ' ').trim();
    cleaned = cleaned.replaceAll(RegExp(r'_{2,}'), ' ').trim();
    return _stripLeadingPunctuation(cleaned);
  }

  /// Removes leading colons/dots/dashes/whitespace - the separator a label
  /// like "PART NO:" or "LOCATION -" leaves behind once the label itself
  /// has been cut off, so it never ends up stuck onto the extracted value.
  static String _stripLeadingPunctuation(String s) {
    return s.replaceFirst(RegExp(r'^[:.\-\s]+'), '').trim();
  }
}
