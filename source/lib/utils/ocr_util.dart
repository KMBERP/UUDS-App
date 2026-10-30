import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../db/db_helper.dart';

/// High-accuracy on-device text recognition and tag extraction for aviation tags.
///
/// Uses spatial 2D bounding-box layout analysis (same-row right, column-below),
/// multi-label collision avoidance, and aviation part-number heuristics.
class OcrUtil {
  static const List<String> _partNoLabels = [
    'PART NO',
    'PART NUMBER',
    'PART NO.',
    'PARTNO',
    'P/N',
    'P.N.',
    'P / N',
    'ASSY P/N',
    'ASSY NO',
    'PART #',
    'ITEM NO',
  ];

  static const List<String> _descLabels = [
    'DESCRIPTION',
    'DESC.',
    'DESC',
    'NOMENCLATURE',
    'ITEM NAME',
    'PART NAME',
    'ITEM DESC',
  ];

  static const List<String> _locLabels = [
    'LOCATION',
    'LOC.',
    'LOC',
    'BIN/LOC',
    'BIN',
    'REMOVED FROM',
    'INSTALL LOC',
    'STATION',
  ];

  static const List<String> _qtyLabels = [
    'QTY',
    'QUANTITY',
    'QTY.',
    'COUNT',
    'QNTY',
    'TOTAL QTY',
    'PCS',
  ];

  static const List<String> _allKnownLabels = [
    ..._partNoLabels,
    ..._descLabels,
    ..._locLabels,
    ..._qtyLabels,
    'SERIAL NO',
    'SERIAL',
    'S/N',
    'SER NO',
    'DATE',
    'SIGNATURE',
    'SIGN',
    'STATUS',
    'SERVICEABLE',
    'UNSERVICEABLE',
    'SCRAP',
    'REASON',
    'WORK ORDER',
    'W/O',
    'BATCH',
    'ENGINEERING',
    'DEPARTMENT',
    'INSPECTED BY',
    'AIRCRAFT',
  ];

  static Future<Map<String, String>> extractTagFields(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await recognizer.processImage(inputImage);

      final lines = <_OcrLine>[];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final cleaned = _cleanRawLine(line.text);
          if (cleaned.isNotEmpty) {
            lines.add(_OcrLine(
              rawText: line.text,
              cleanedText: cleaned,
              upperText: cleaned.toUpperCase(),
              box: line.boundingBox,
            ));
          }
        }
      }

      // Sort lines top-to-bottom, then left-to-right
      lines.sort((a, b) {
        final dy = (a.box.top - b.box.top).abs();
        if (dy < 12) return a.box.left.compareTo(b.box.left);
        return a.box.top.compareTo(b.box.top);
      });

      String partNo = _extractField(lines, _partNoLabels);
      String description = _extractField(lines, _descLabels);
      String location = _extractField(lines, _locLabels);
      String qty = _extractField(lines, _qtyLabels);

      // Heuristic fallback for Part No if label was missed
      if (partNo.isEmpty || _isLikelyLabelOnly(partNo)) {
        partNo = _findAviationPartNoFallback(lines);
      }

      // Snap location to known aircraft lavatory/cabin locations if close match
      location = _normalizeLocation(location);

      // Normalize Quantity: extract pure digits, fallback to 1
      qty = _normalizeQty(qty);

      return {
        'partNo': partNo.toUpperCase().trim(),
        'description': description.toUpperCase().trim(),
        'location': location.toUpperCase().trim(),
        'tagQty': qty,
        'rawText': recognizedText.text,
      };
    } catch (e) {
      return {
        'partNo': '',
        'description': '',
        'location': '',
        'tagQty': '1',
        'rawText': '',
        'error': e.toString(),
      };
    } finally {
      await recognizer.close();
    }
  }

  /// Extracts value using both inline search and spatial bounding-box column lookup
  static String _extractField(List<_OcrLine> lines, List<String> targetLabels) {
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      for (final label in targetLabels) {
        final idx = line.upperText.indexOf(label);
        if (idx == -1) continue;

        // 1. Check remainder on the same line
        final remainder = line.cleanedText.substring(idx + label.length).trim();
        final inlineVal = _stripLeadingSeparators(remainder);

        // Check if inline value is present and not immediately interrupted by another label
        if (inlineVal.isNotEmpty) {
          final cutVal = _truncateAtNextLabel(inlineVal);
          if (cutVal.isNotEmpty && !_isLikelyLabelOnly(cutVal)) {
            return cutVal;
          }
        }

        // 2. Spatial lookup: Check line directly below this label (e.g. table/box layout)
        final belowVal = _findLineDirectlyBelow(lines, line, i);
        if (belowVal.isNotEmpty && !_isLikelyLabelOnly(belowVal)) {
          return belowVal;
        }
      }
    }
    return '';
  }

  /// Finds a text line physically positioned directly below [targetLine] within reasonable bounding box bounds
  static String _findLineDirectlyBelow(List<_OcrLine> allLines, _OcrLine targetLine, int targetIndex) {
    _OcrLine? bestCandidate;
    double minDistance = double.infinity;

    for (int j = 0; j < allLines.length; j++) {
      if (j == targetIndex) continue;
      final cand = allLines[j];

      // Must be below the target line
      final verticalGap = cand.box.top - targetLine.box.bottom;
      if (verticalGap < -4 || verticalGap > (targetLine.box.height * 3.5)) continue;

      // Must have horizontal overlap or close horizontal alignment
      final horizontalOverlap = (cand.box.left < targetLine.box.right + 30) &&
                                (cand.box.right > targetLine.box.left - 30);
      if (!horizontalOverlap) continue;

      // Disqualify if it's another known label
      if (_isLikelyLabelOnly(cand.upperText)) continue;

      if (verticalGap < minDistance) {
        minDistance = verticalGap;
        bestCandidate = cand;
      }
    }

    if (bestCandidate != null) {
      return _stripLeadingSeparators(bestCandidate.cleanedText);
    }
    return '';
  }

  /// Truncates string if another label begins on the same line (e.g. "BACB30NE4-10 QTY: 2")
  static String _truncateAtNextLabel(String s) {
    final upper = s.toUpperCase();
    int earliest = s.length;
    for (final l in _allKnownLabels) {
      final pos = upper.indexOf(l);
      if (pos > 0 && pos < earliest) {
        earliest = pos;
      }
    }
    return s.substring(0, earliest).trim();
  }

  static bool _isLikelyLabelOnly(String s) {
    final upper = s.trim().toUpperCase();
    for (final l in _allKnownLabels) {
      if (upper == l || upper == '$l:' || upper == '$l -' || upper == '$l.') {
        return true;
      }
    }
    return false;
  }

  /// Searches lines for standard aviation part number patterns (alphanumeric with dashes/slashes)
  static String _findAviationPartNoFallback(List<_OcrLine> lines) {
    // Standard aerospace part syntax: e.g. BACB30NE4-10, D28271000-001, NAS1149F0332P, 10-60477-1
    final aviationRegex = RegExp(r'\b[A-Z0-9]{2,10}[-\/][A-Z0-9\-\/]{2,15}\b');
    for (final line in lines) {
      if (_isLikelyLabelOnly(line.upperText)) continue;
      // Skip date lines
      if (RegExp(r'\b\d{2}[-\/][A-Z]{3}[-\/]\d{2,4}\b').hasMatch(line.upperText)) continue;
      if (RegExp(r'\b\d{4}[-\/]\d{2}[-\/]\d{2}\b').hasMatch(line.upperText)) continue;
      // Skip aircraft regs like A6-XXX
      if (RegExp(r'\bA6-[A-Z]{3}\b').hasMatch(line.upperText)) continue;

      final match = aviationRegex.firstMatch(line.upperText);
      if (match != null) {
        return match.group(0)!;
      }
    }
    return '';
  }

  /// Snaps extracted location to canonical locations (e.g. LAV 1MC)
  static String _normalizeLocation(String raw) {
    if (raw.isEmpty) return '';
    final cleaned = raw.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
    for (final loc in kDefaultPartLocations) {
      final canonicalCleaned = loc.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
      if (cleaned == canonicalCleaned || cleaned.contains(canonicalCleaned)) {
        return loc;
      }
    }
    return _stripLeadingSeparators(raw);
  }

  static String _normalizeQty(String raw) {
    if (raw.isEmpty) return '1';
    final digits = RegExp(r'\d+').firstMatch(raw);
    if (digits != null && digits.group(0) != null) {
      return digits.group(0)!;
    }
    return '1';
  }

  static String _cleanRawLine(String line) {
    var s = line.replaceAll(RegExp(r'\.{2,}'), ' ').trim();
    s = s.replaceAll(RegExp(r'_{2,}'), ' ').trim();
    return s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  static String _stripLeadingSeparators(String s) {
    return s.replaceFirst(RegExp(r'^[:.\-=\s#]+'), '').trim();
  }
}

class _OcrLine {
  final String rawText;
  final String cleanedText;
  final String upperText;
  final Rect box;

  _OcrLine({
    required this.rawText,
    required this.cleanedText,
    required this.upperText,
    required this.box,
  });
}
