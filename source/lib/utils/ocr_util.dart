import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../db/db_helper.dart';

/// High-accuracy on-device text recognition and tag extraction for aviation tags.
///
/// Tailored for Emirates Engineering Component Identification Tags and airline store slips.
/// Uses spatial 2D bounding-box layout analysis, multi-label collision avoidance,
/// dotted line stripping, and candidate token harvesting for instant 1-tap review.
class OcrUtil {
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
    'P / N',
    'ASSY P/N:',
    'ASSY P/N',
    'ASSY NO:',
    'ASSY NO',
    'PART #:',
    'PART #',
    'ITEM NO:',
    'ITEM NO',
    'MATERIAL NO:',
    'MATERIAL NO',
    'MAT NO:',
    'MAT NO',
    'MAT. NO:',
    'MAT. NO',
    'SAP NO:',
    'SAP NO',
  ];

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
    'ITEM DESC:',
    'ITEM DESC',
  ];

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
    'REMOVED FROM:',
    'REMOVED FROM',
    'INSTALL LOC:',
    'INSTALL LOC',
    'STATION:',
    'STATION',
  ];

  static const List<String> _qtyLabels = [
    'QTY.:',
    'QTY:',
    'QTY.',
    'QTY',
    'QUANTITY:',
    'QUANTITY',
    'COUNT:',
    'COUNT',
    'QNTY:',
    'QNTY',
    'TOTAL QTY:',
    'TOTAL QTY',
    'PCS:',
    'PCS',
    'EA:',
    'EA',
  ];

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

  static const List<String> _allKnownLabels = [
    ..._partNoLabels,
    ..._descLabels,
    ..._locLabels,
    ..._qtyLabels,
    ..._serialLabels,
    'ACCESS PANEL NO.:',
    'ACCESS PANEL NO:',
    'ACCESS PANEL NO',
    'FIN/EQUIPNO:',
    'FIN/EQUIPNO',
    'REASON FOR REMOVAL:',
    'REASON FOR REMOVAL',
    'INSPECTED:',
    'INSPECTED',
    'STAFF NUMBER:',
    'STAFF NUMBER',
    'A/C REGN.:',
    'A/C REGN:',
    'A/C REGN',
    'AIRCRAFT COMPONENT IDENTIFICATION TAG',
    'ENGINEERING DEPARTMENT',
    'EMIRATES',
    'NAME:',
    'NAME',
    'DATE:',
    'DATE',
    'STATUS',
    'SERVICEABLE',
    'UNSERVICEABLE',
    'SCRAP',
    'WORK ORDER',
    'W/O',
    'BATCH',
  ];

  static Future<Map<String, dynamic>> extractTagFields(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await recognizer.processImage(inputImage);

      final lines = <_OcrLine>[];
      final rawCandidateLines = <String>[];

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
            final trimmed = cleaned.trim();
            if (trimmed.length >= 2 && !rawCandidateLines.contains(trimmed)) {
              rawCandidateLines.add(trimmed);
            }
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
      String serialNo = _extractField(lines, _serialLabels);

      // Heuristic fallback for Part No if label search missed it
      if (partNo.isEmpty || _isLikelyLabelOnly(partNo)) {
        partNo = _findAviationPartNoFallback(lines);
      }

      // Snap location to known aircraft lavatory/cabin locations if close match
      location = _normalizeLocation(location);

      // Normalize Quantity: extract pure digits, handle '15.00 EA' or '1 EA'
      qty = _normalizeQty(qty);

      // Prepare clean candidate chips (removing pure static headers like 'EMIRATES' or 'ENGINEERING DEPARTMENT')
      final filteredCandidates = <String>[];
      for (final cand in rawCandidateLines) {
        final up = cand.toUpperCase().trim();
        if (up == 'EMIRATES' ||
            up == 'ENGINEERING DEPARTMENT' ||
            up.contains('QA/F/0363') ||
            up.contains('AIRCRAFT COMPONENT IDENTIFICATION') ||
            up == 'INSPECTED:' ||
            up == 'NAME:' ||
            up.length <= 1) {
          continue;
        }
        // If candidate contains label with separator e.g. "DESCRIPTION: FOLDABLE TABLE", also extract the value
        final stripped = _stripAnyKnownPrefix(cand);
        if (stripped.isNotEmpty && stripped != cand && !filteredCandidates.contains(stripped)) {
          filteredCandidates.add(stripped);
        }
        if (!filteredCandidates.contains(cand)) {
          filteredCandidates.add(cand);
        }
      }

      return {
        'partNo': partNo.toUpperCase().trim(),
        'description': description.toUpperCase().trim(),
        'location': location.toUpperCase().trim(),
        'tagQty': qty,
        'serialNo': serialNo.toUpperCase().trim(),
        'rawText': recognizedText.text,
        'candidates': filteredCandidates,
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
      if (verticalGap < -4 || verticalGap > (targetLine.box.height * 4.0)) continue;

      // Must have horizontal overlap or close horizontal alignment
      final horizontalOverlap = (cand.box.left < targetLine.box.right + 40) &&
                                (cand.box.right > targetLine.box.left - 40);
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

  /// Truncates string if another label begins on the same line (e.g. "13408A S/NO: 9000081255")
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
      if (upper == l ||
          upper == '$l:' ||
          upper == '$l -' ||
          upper == '$l.' ||
          upper == '$l.:') {
        return true;
      }
    }
    return false;
  }

  /// Strip any recognized label prefix from candidate lines (e.g. "DESCRIPTION: BUSTLE STOWAGE" -> "BUSTLE STOWAGE")
  static String _stripAnyKnownPrefix(String s) {
    final upper = s.toUpperCase().trim();
    for (final l in _allKnownLabels) {
      if (upper.startsWith(l)) {
        final remainder = s.trim().substring(l.length).trim();
        return _stripLeadingSeparators(remainder);
      }
    }
    return s.trim();
  }

  /// Searches lines for standard aviation part number patterns (alphanumeric with dashes/slashes)
  static String _findAviationPartNoFallback(List<_OcrLine> lines) {
    // Standard aerospace part syntax: e.g. BACB30NE4-10, D28271000-001, NAS1149F0332P, 10-60477-1, UAE37-212-1
    final aviationRegex = RegExp(r'\b[A-Z0-9]{2,10}[-\/][A-Z0-9\-\/]{2,15}\b');
    for (final line in lines) {
      if (_isLikelyLabelOnly(line.upperText)) continue;
      // Skip date lines
      if (RegExp(r'\b\d{2}[-\/][A-Z]{3}[-\/]\d{2,4}\b').hasMatch(line.upperText)) continue;
      if (RegExp(r'\b\d{2,4}[-\/]\d{2}[-\/]\d{2,4}\b').hasMatch(line.upperText)) continue;
      // Skip aircraft regs like A6-XXX
      if (RegExp(r'\bA6-[A-Z0-9]{3}\b').hasMatch(line.upperText)) continue;

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
    // Extracts numeric value even if followed by EA, PCS, NOS, e.g. "15.00 EA" -> "15"
    final decimalMatch = RegExp(r'(\d+)(?:\.\d+)?').firstMatch(raw);
    if (decimalMatch != null && decimalMatch.group(1) != null) {
      return decimalMatch.group(1)!;
    }
    return '1';
  }

  static String _cleanRawLine(String line) {
    // Strips repeated dots, dashes, underscores common on pre-printed form guide lines
    var s = line.replaceAll(RegExp(r'\.{2,}'), ' ').trim();
    s = s.replaceAll(RegExp(r'_{2,}'), ' ').trim();
    s = s.replaceAll(RegExp(r'-{3,}'), ' ').trim();
    return s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  static String _stripLeadingSeparators(String s) {
    return s.replaceFirst(RegExp(r'^[:.\-=\s#_]+'), '').trim();
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
