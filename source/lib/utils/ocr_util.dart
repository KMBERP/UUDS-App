import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../db/db_helper.dart';

/// High-accuracy on-device text recognition and tag extraction for aviation tags.
///
/// Specifically optimized for Emirates Engineering Component Identification Tags
/// (QA/F/0363 Rev. 03) and airline store repair tags.
///
/// Handles:
/// - Inline labels with dotted guidelines (e.g. `PART NO.:.... 13408A S/NO:.... 9000081255`)
/// - Rotated/portrait tags photographed in maintenance hangars
/// - Multi-line split values where label and handwriting appear on adjacent lines
/// - Candidate chip harvesting for 1-tap review and assignment in UI
class OcrUtil {
  /// Labels for identifying part number
  static const List<String> _partNoLabels = [
    'PART NO.:',
    'PART NO.',
    'PART NO:',
    'PART NO',
    'PART NUMBER:',
    'PART NUMBER',
    'PARTNO',
    'P/N:',
    'P/N',
    'P.N.:',
    'P.N.',
    'ASSY P/N:',
    'ASSY P/N',
    'ASSY NO:',
    'ASSY NO',
    'PART #:',
    'PART #',
    'MATERIAL NO:',
    'MATERIAL NO',
  ];

  /// Labels for identifying part description
  static const List<String> _descLabels = [
    'DESCRIPTION.:',
    'DESCRIPTION:',
    'DESCRIPTION',
    'DESC.:',
    'DESC:',
    'DESC.',
    'DESC',
    'NOMENCLATURE:',
    'NOMENCLATURE',
    'ITEM NAME:',
    'ITEM NAME',
    'PART NAME:',
    'PART NAME',
  ];

  /// Labels for identifying aircraft location
  static const List<String> _locLabels = [
    'LOCATION.:',
    'LOCATION:',
    'LOCATION',
    'LOC.:',
    'LOC:',
    'LOC.',
    'LOC',
    'BIN/LOC:',
    'BIN/LOC',
    'BIN:',
    'BIN',
    'STATION:',
    'STATION',
  ];

  /// Labels for serial number
  static const List<String> _serialLabels = [
    'S/NO.:',
    'S/NO:',
    'S/NO',
    'S/N.:',
    'S/N:',
    'S/N',
    'SERIAL NO.:',
    'SERIAL NO:',
    'SERIAL NO',
    'SERIAL:',
    'SERIAL',
    'SER NO.:',
    'SER NO:',
    'SER NO',
  ];

  /// Labels for aircraft registration
  static const List<String> _regLabels = [
    'A/C REGN.:',
    'A/C REGN:',
    'A/C REGN',
    'A/C REG.:',
    'A/C REG:',
    'A/C REG',
    'AC REGN:',
    'AC REGN',
    'REGN.:',
    'REGN:',
    'REGN',
  ];

  /// Known multi-character labels used to safely delimit values
  static const List<String> _delimiters = [
    'S/NO',
    'S/N',
    'ACCESS PANEL',
    'FIN/EQUIPNO',
    'REASON FOR REMOVAL',
    'INSPECTED',
    'STAFF NUMBER',
    'LOCATION',
    'DESCRIPTION',
    'PART NO',
    'PART NUMBER',
    'P/N',
    'A/C REGN',
    'A/C REG',
    'NAME',
    'DATE',
    'STATUS',
    'SERVICEABLE',
    'UNSERVICEABLE',
  ];

  /// Main tag extraction method
  static Future<Map<String, dynamic>> extractTagFields(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await recognizer.processImage(inputImage);

      final rawText = recognizedText.text;
      final cleanedFullText = _cleanDottedLines(rawText);

      // Collect all lines across all blocks
      final rawLines = <String>[];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final trimmed = _cleanDottedLines(line.text).trim();
          if (trimmed.isNotEmpty && !rawLines.contains(trimmed)) {
            rawLines.add(trimmed);
          }
        }
      }

      // Strategy 1: High-precision Regex Extraction over full text
      String partNo = _extractByRegex(
        cleanedFullText,
        r'PART\s*N[O0][\.\:]*\s*(.*?)(?=\s*(?:S\/?N[O0]|ACCESS|FIN|REASON|LOCATION|DESCRIPTION|\n|$))',
      );

      String description = _extractByRegex(
        cleanedFullText,
        r'DESC(?:RIPTION)?[\.\:]*\s*(.*?)(?=\s*(?:LOCATION|PART\s*N[O0]|S\/?N[O0]|ACCESS|FIN|REASON|\n|$))',
      );

      String location = _extractByRegex(
        cleanedFullText,
        r'LOC(?:ATION)?[\.\:]*\s*(.*?)(?=\s*(?:DESCRIPTION|PART\s*N[O0]|S\/?N[O0]|ACCESS|FIN|REASON|\n|$))',
      );

      String serialNo = _extractByRegex(
        cleanedFullText,
        r'S\/?N[O0][\.\:]*\s*(.*?)(?=\s*(?:ACCESS|FIN|REASON|LOCATION|DESCRIPTION|PART|\n|$))',
      );

      // Strategy 2: Line-by-line fallback (for split-line layout where label and value are on separate lines)
      if (partNo.isEmpty || _isLikelyLabelOnly(partNo)) {
        partNo = _extractFromLines(rawLines, _partNoLabels);
      }
      if (description.isEmpty || _isLikelyLabelOnly(description)) {
        description = _extractFromLines(rawLines, _descLabels);
      }
      if (location.isEmpty || _isLikelyLabelOnly(location)) {
        location = _extractFromLines(rawLines, _locLabels);
      }
      if (serialNo.isEmpty || _isLikelyLabelOnly(serialNo)) {
        serialNo = _extractFromLines(rawLines, _serialLabels);
      }

      // Strategy 3: Aviation Part Number Pattern Fallback (Emirates UAE series & standard aerospace part numbers)
      if (partNo.isEmpty || _isLikelyLabelOnly(partNo)) {
        partNo = _findAviationPartNoFallback(cleanedFullText, rawLines);
      }

      // Snap location to canonical aircraft locations if matching
      location = _normalizeLocation(location);

      // Normalize Quantity: extract pure digits, handle '15.00 EA' or default '1'
      final qty = _extractQty(cleanedFullText);

      // Build clean candidate chips for 1-tap review
      final candidates = _buildCandidates(rawLines, partNo, description, location, serialNo);

      return {
        'partNo': partNo.toUpperCase().trim(),
        'description': description.toUpperCase().trim(),
        'location': location.toUpperCase().trim(),
        'tagQty': qty,
        'serialNo': serialNo.toUpperCase().trim(),
        'rawText': rawText,
        'candidates': candidates,
      };
    } catch (e) {
      return {
        'partNo': '',
        'description': '',
        'location': '',
        'tagQty': '1',
        'serialNo': '',
        'rawText': '',
        'candidates': <String>[],
        'error': e.toString(),
      };
    } finally {
      await recognizer.close();
    }
  }

  /// Extracts field using regex with lookahead boundary
  static String _extractByRegex(String text, String pattern) {
    try {
      final reg = RegExp(pattern, caseSensitive: false);
      final match = reg.firstMatch(text);
      if (match != null && match.groupCount >= 1) {
        final val = match.group(1)?.trim() ?? '';
        return _cleanFieldValue(val);
      }
    } catch (_) {}
    return '';
  }

  /// Searches recognized lines for [labels] and returns inline remainder or next line
  static String _extractFromLines(List<String> lines, List<String> labels) {
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final upper = line.toUpperCase();

      for (final label in labels) {
        final idx = upper.indexOf(label);
        if (idx == -1) continue;

        // Check inline remainder on the same line
        final remainder = line.substring(idx + label.length).trim();
        final cleanedInline = _cleanFieldValue(_truncateAtDelimiters(remainder));
        if (cleanedInline.isNotEmpty && !_isLikelyLabelOnly(cleanedInline)) {
          return cleanedInline;
        }

        // If line only had the label, check the NEXT line
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1].trim();
          if (!_isLikelyLabelOnly(nextLine) && nextLine.length >= 2) {
            final cleanedNext = _cleanFieldValue(_truncateAtDelimiters(nextLine));
            if (cleanedNext.isNotEmpty) {
              return cleanedNext;
            }
          }
        }
      }
    }
    return '';
  }

  /// Searches text and lines for standard aviation and Emirates part number syntaxes
  static String _findAviationPartNoFallback(String fullText, List<String> lines) {
    // 1. Emirates UAE series: e.g. UAE 37-312-1, UAE37-212-1
    final uaeMatch = RegExp(r'\bUAE\s*\d{2}[-\s]\d{2,4}[-\s]\d+\b', caseSensitive: false).firstMatch(fullText);
    if (uaeMatch != null) {
      return uaeMatch.group(0)!.trim();
    }

    // 2. Alphanumeric part numbers with letters at end or middle (e.g. 13408A, 1003479A00000, 10-60477-1)
    final alphaMatch = RegExp(r'\b\d{4,12}[A-Z]\d*\b').firstMatch(fullText);
    if (alphaMatch != null) {
      return alphaMatch.group(0)!.trim();
    }

    // 3. Aerospace vendor prefix syntax: e.g. HIS03-79784, BACB30NE4-10, NAS1149F0332P
    final vendorMatch = RegExp(r'\b[A-Z]{2,6}\d{2,10}[A-Z0-9\-]*\b').firstMatch(fullText);
    if (vendorMatch != null && !_isLikelyLabelOnly(vendorMatch.group(0)!)) {
      return vendorMatch.group(0)!.trim();
    }

    // 4. Standard hyphenated aerospace part numbers
    final hyphenMatch = RegExp(r'\b[A-Z0-9]{2,10}[-\/][A-Z0-9\-\/]{2,15}\b').firstMatch(fullText);
    if (hyphenMatch != null) {
      final cand = hyphenMatch.group(0)!.trim();
      // Avoid dates (e.g. 26-10-26) and A6- registrations
      if (!RegExp(r'^\d{2}[-\/]\d{2}[-\/]\d{2,4}$').hasMatch(cand) &&
          !RegExp(r'^A6-[A-Z0-9]{3}$').hasMatch(cand)) {
        return cand;
      }
    }

    return '';
  }

  /// Truncates string when another major label appears (without breaking on short subwords like 'EA')
  static String _truncateAtDelimiters(String s) {
    final upper = s.toUpperCase();
    int earliest = s.length;

    for (final delim in _delimiters) {
      // Must match at word boundary or with colon/dot
      final pattern = RegExp('\\b' + RegExp.escape(delim) + r'[:\.\s]', caseSensitive: false);
      final match = pattern.firstMatch(upper);
      if (match != null && match.start > 0 && match.start < earliest) {
        earliest = match.start;
      }
    }

    return s.substring(0, earliest).trim();
  }

  /// Cleans repeated dots, underscores, dashes, and bullet marks common on pre-printed forms
  static String _cleanDottedLines(String s) {
    // Normalizes patterns like "....", ". . . .", "______", "-----"
    var res = s.replaceAll(RegExp(r'(?:[\.\-_·•\s]{2,}\.|\.{2,}|_{2,}|-{2,})'), ' ');
    return res.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  /// Cleans field values by stripping leading/trailing punctuation and quotation marks
  static String _cleanFieldValue(String s) {
    var val = s.trim();
    // Strip leading colons, dots, dashes, hash signs
    val = val.replaceFirst(RegExp(r'^[:.\-=\s#_]+'), '').trim();
    // Strip trailing colons or stray dashes
    val = val.replaceFirst(RegExp(r'[:.\-=\s#_]+$'), '').trim();
    return val;
  }

  /// Checks if a string is solely a pre-printed form label
  static bool _isLikelyLabelOnly(String s) {
    final upper = s.trim().toUpperCase();
    if (upper.isEmpty || upper == '-' || upper == 'N/A' || upper == 'NONE') return true;

    for (final d in _delimiters) {
      if (upper == d ||
          upper == '$d:' ||
          upper == '$d.' ||
          upper == '$d.:' ||
          upper == '$d -') {
        return true;
      }
    }
    return false;
  }

  /// Snaps extracted location to canonical list (e.g. FWD BAR LH LOWER, UR1 MD, LAV 1MC)
  static String _normalizeLocation(String raw) {
    if (raw.isEmpty) return '';
    final cleaned = raw.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
    for (final loc in kDefaultPartLocations) {
      final canonicalCleaned = loc.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
      if (cleaned == canonicalCleaned || cleaned.contains(canonicalCleaned)) {
        return loc;
      }
    }
    return _cleanFieldValue(raw);
  }

  /// Extracts quantity or defaults to '1'
  static String _extractQty(String text) {
    final match = RegExp(r'\b(?:QTY|QUANTITY)[\.\:]*\s*(\d+)', caseSensitive: false).firstMatch(text);
    if (match != null && match.group(1) != null) {
      return match.group(1)!;
    }
    return '1';
  }

  /// Builds candidate chips for the 1-tap review dialog
  static List<String> _buildCandidates(
    List<String> lines,
    String partNo,
    String description,
    String location,
    String serialNo,
  ) {
    final list = <String>[];

    void addCandidate(String s) {
      final t = s.trim();
      if (t.length >= 2 && !list.contains(t) && !_isBoilerplate(t)) {
        list.add(t);
      }
    }

    if (partNo.isNotEmpty) addCandidate(partNo);
    if (description.isNotEmpty) addCandidate(description);
    if (location.isNotEmpty) addCandidate(location);
    if (serialNo.isNotEmpty && serialNo != '-') addCandidate(serialNo);

    for (final line in lines) {
      final trimmed = _cleanFieldValue(_truncateAtDelimiters(line));
      if (trimmed.isNotEmpty) {
        addCandidate(trimmed);
      }
    }

    return list;
  }

  /// Checks if string is pure boilerplate header
  static bool _isBoilerplate(String s) {
    final up = s.toUpperCase().trim();
    return up == 'EMIRATES' ||
        up == 'ENGINEERING DEPARTMENT' ||
        up.contains('QA/F/0363') ||
        up.contains('AIRCRAFT COMPONENT IDENTIFICATION') ||
        up.contains('LAE STAMP') ||
        up.contains('INSPECTION PERFORMED') ||
        up == 'INSPECTED:' ||
        up == 'INSPECTED' ||
        up == 'ACCESS PANEL NO' ||
        up == 'FIN/EQUIPNO' ||
        up == 'REV. 03' ||
        up == 'REV 03' ||
        up == '-' ||
        _isLikelyLabelOnly(up);
  }
}
