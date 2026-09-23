// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Extracts text from document files (PDF, DOCX) so they can be
/// fed into local or cloud LLMs as context.
/// PDF text is returned as markdown (plain text is valid markdown).
class DocumentExtractorService {
  /// Extract text from a file based on its extension.
  /// For PDF files, an optional [password] can be provided for protected documents.
  static Future<String> extractText(String path, String extension, {String? password}) async {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return extractPdf(path, password: password);
      case 'docx':
        return _extractDocx(path);
      case 'txt':
      case 'md':
      case 'json':
      case 'csv':
      case 'log':
      case 'yaml':
      case 'yml':
      case 'xml':
      case 'dart':
      case 'kt':
      case 'java':
      case 'js':
      case 'ts':
      case 'py':
        final bytes = await File(path).readAsBytes();
        return utf8.decode(bytes, allowMalformed: true);
      default:
        throw UnsupportedError(
          'Document extraction not supported for .$extension files',
        );
    }
  }

  /// Extract text from a PDF file using Syncfusion PDF.
  static Future<String> extractPdf(String path, {String? password}) async {
    final bytes = await File(path).readAsBytes();
    final document = PdfDocument(inputBytes: bytes, password: password);
    try {
      final extractor = PdfTextExtractor(document);
      final raw = extractor.extractText();
      return _rawToMarkdown(raw);
    } finally {
      document.dispose();
    }
  }

  /// Convert raw PDF-extracted text into lightweight markdown so the LLM
  /// gets structural hints (headers, lists, code blocks, tables) instead of
  /// a flat wall of text.
  ///
  /// Heuristics used:
  /// * Lines ending with '=' or '-' (underlined headers in PDFs) → ## Header
  /// * All-caps short lines → ## Header
  /// * Lines starting with bullet chars (•, -, *, ◦) → list items
  /// * Lines matching "1.", "2." etc. → numbered list
  /// * Consecutive lines with consistent column count → table
  /// * Indented blocks (≥2 spaces at start of every line) → code fence
  static String _rawToMarkdown(String raw) {
    if (raw.isEmpty) return raw;

    final lines = raw.split('\n');
    final out = <String>[];
    int i = 0;

    while (i < lines.length) {
      final line = lines[i];

      // Skip blank lines — we normalise spacing below.
      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      // ── Code block: consecutive indented lines ─────────────────────────
      if (_isIndented(line) && _looksLikeCodeBlock(lines, i)) {
        final codeLines = <String>[];
        while (i < lines.length && _isIndented(lines[i])) {
          codeLines.add(_stripIndent(lines[i]));
          i++;
        }
        out.add('```\n${codeLines.join('\n')}\n```');
        continue;
      }

      // ── Table detection: 3+ consecutive lines with consistent columns ──
      if (_looksLikeTable(lines, i)) {
        final tableLines = <String>[];
        final int colCount = _estimateTableColumns(lines[i]);
        while (i < lines.length &&
            _estimateTableColumns(lines[i]) == colCount &&
            tableLines.length < 50) {
          tableLines.add(_lineToTableRow(lines[i]));
          i++;
        }
        if (tableLines.length >= 2) {
          out.addAll(tableLines);
          out.add(''); // blank line after table
        }
        continue;
      }

      // ── Bullet / numbered list ────────────────────────────────────────
      final bulletMatch = RegExp(r'^\s*([•\-\*◦]|\d+\.)\s+(.*)').firstMatch(line);
      if (bulletMatch != null) {
        final itemType = bulletMatch.group(1)!.trim();
        final isNumbered = RegExp(r'^\d+\.$').hasMatch(itemType);
        final content = bulletMatch.group(2)!;
        final listLines = <String>[if (isNumbered) '1. $content' else '- $content'];
        i++;
        while (i < lines.length) {
          final nextBullet = RegExp(r'^\s*([•\-\*◦]|\d+\.)\s+(.*)').firstMatch(lines[i]);
          if (nextBullet == null) break;
          final nextType = nextBullet.group(1)!.trim();
          final nextContent = nextBullet.group(2)!;
          if (isNumbered && !RegExp(r'^\d+\.$').hasMatch(nextType)) break;
          if (!isNumbered && RegExp(r'^\d+\.$').hasMatch(nextType)) break;
          listLines.add(isNumbered ? '${listLines.length + 1}. $nextContent' : '- $nextContent');
          i++;
        }
        out.addAll(listLines);
        continue;
      }

      // ── Underlined header ("Title\n===") ──────────────────────────────
      if (line.trim().isNotEmpty &&
          line.length < 100 &&
          (line.trim().endsWith('=') || line.trim().endsWith('-'))) {
        out.add('## ${line.trim().replaceAll(RegExp(r'[=\-]+$'), '').trim()}');
        i++;
        continue;
      }

      // ── All-caps short line → header ──────────────────────────────────
      if (_isAllCaps(line) && line.trim().length < 100) {
        out.add('## ${line.trim()}');
        i++;
        continue;
      }

      // ── Normal paragraph ──────────────────────────────────────────────
      final paraLines = <String>[line];
      i++;
      while (i < lines.length &&
          !lines[i].trim().isEmpty &&
          !RegExp(r'^\s*([•\-\*◦]|\d+\.)\s+').hasMatch(lines[i]) &&
          !(_isIndented(lines[i]) && _looksLikeCodeBlock(lines, i))) {
        paraLines.add(lines[i]);
        i++;
      }
      out.add(paraLines.join(' '));
    }

    // Collapse multiple blank lines into one.
    final result = out.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return result.trim();
  }

  static bool _isIndented(String line) =>
      line.isNotEmpty && (line[0] == ' ' || line[0] == '\t') && line.trim().isNotEmpty;

  static bool _looksLikeCodeBlock(List<String> lines, int start) {
    int count = 0;
    for (int j = start; j < lines.length && j < start + 4; j++) {
      if (_isIndented(lines[j])) count++;
    }
    return count >= 3;
  }

  static String _stripIndent(String line) {
    final m = RegExp(r'^(\s+)').firstMatch(line);
    return m != null ? line.substring(m.group(1)!.length) : line;
  }

  static int _estimateTableColumns(String line) {
    if (line.contains('\t')) return line.split('\t').length;
    if (line.contains('|')) return line.split('|').length - 2;
    final parts = line.trim().split(RegExp(r'\s{2,}'));
    return parts.length;
  }

  static bool _looksLikeTable(List<String> lines, int start) {
    if (start + 2 >= lines.length) return false;
    final int cols = _estimateTableColumns(lines[start]);
    if (cols < 2) return false;
    int matches = 0;
    for (int j = start; j < lines.length && j < start + 5; j++) {
      if (_estimateTableColumns(lines[j]) == cols) matches++;
    }
    return matches >= 3;
  }

  static String _lineToTableRow(String line) {
    if (line.contains('\t')) {
      final cells = line.split('\t').map((c) => c.trim()).toList();
      return '| ${cells.join(' | ')} |';
    }
    if (line.contains('|')) return line.replaceAll(RegExp(r'\s*\|\s*'), ' | ').trim();
    final parts = line.trim().split(RegExp(r'\s{2,}'));
    if (parts.length >= 2) return '| ${parts.map((p) => p.trim()).join(' | ')} |';
    return line.trim();
  }

  static bool _isAllCaps(String line) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty && trimmed.length < 3) return false;
    return trimmed.contains(RegExp(r'[A-Za-z]')) && trimmed == trimmed.toUpperCase();
  }

  /// Extract text from a DOCX file using pure Dart (archive + xml).
  static Future<String> _extractDocx(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final documentFile = archive.files.firstWhere(
      (f) => f.name == 'word/document.xml',
      orElse: () => throw Exception('Invalid DOCX: word/document.xml not found'),
    );

    final xmlString = utf8.decode(documentFile.content as List<int>);
    final document = XmlDocument.parse(xmlString);

    // Preserve paragraph breaks: <w:p> elements separate paragraphs.
    final paragraphs = <String>[];
    for (final p in document.findAllElements('w:p')) {
      final pTexts = p.findAllElements('w:t').map((e) => e.value).join();
      if (pTexts.isNotEmpty) paragraphs.add(pTexts);
    }

    return paragraphs.isNotEmpty
        ? paragraphs.join('\n\n')
        : document.findAllElements('w:t').map((e) => e.value).join();
  }
}
