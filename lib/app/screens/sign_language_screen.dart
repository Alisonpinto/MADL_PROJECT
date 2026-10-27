import 'dart:async';

import 'package:flutter/material.dart';

import '../feature/auslan_scripts/auslan_predict.dart';
import '../feature/auslan_scripts/sign_language_camera_card.dart';
import '../services/app_announcer.dart';
import '../services/translation_history_service.dart';
import '../widgets/module_bottom_sheet.dart';
import '../widgets/module_header.dart';

class SignLanguageScreen extends StatefulWidget {
  const SignLanguageScreen({
    super.key,
    this.bottomPadding = 0,
  });

  final double bottomPadding;

  @override
  State<SignLanguageScreen> createState() => _SignLanguageScreenState();
}

class _SignLanguageScreenState extends State<SignLanguageScreen> {
  final TranslationHistoryService _historyService = TranslationHistoryService();
  final AuslanPredictor _predictor = AuslanPredictor();
  final List<TranslationHistoryEntry> _history = <TranslationHistoryEntry>[];
  final Set<int> _retryingIndices = <int>{};
  String _allLetters = '';
  String _meaning = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
  }

  Future<void> _loadHistory() async {
    final loaded = await _historyService.load();
    if (!mounted) return;
    setState(() => _history
      ..clear()
      ..addAll(loaded));
  }

  Future<void> _saveTranslation({
    required String capturedLetters,
    required String? guessedText,
  }) async {
    final trimmedLetters = capturedLetters.trim();
    if (trimmedLetters.isEmpty) return;

    final resolvedMeaning = (guessedText != null && guessedText.trim().isNotEmpty)
        ? guessedText.trim()
        : 'Pending translation';

    final persisted = await _historyService.saveEntry(
      text: trimmedLetters,
      meaning: resolvedMeaning,
    );

    if (!mounted) return;
    setState(() {
      _history
        ..clear()
        ..addAll(persisted);
      _allLetters = '';
      _meaning = resolvedMeaning;
    });
  }

  Future<void> _retryTranslation(int index, TranslationHistoryEntry entry) async {
    if (_retryingIndices.contains(index)) return;
    setState(() => _retryingIndices.add(index));

    try {
      final result = await _predictor.guessWordPhrase(entry.text);
      if (result != null && result.isNotEmpty) {
        AppAnnouncer.instance.speak(result);
        final updated = await _historyService.updateEntry(index, result);
        if (mounted) {
          setState(() {
            _history
              ..clear()
              ..addAll(updated);
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not translate text. Check network and API key.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Retry translation error: $e');
    } finally {
      if (mounted) {
        setState(() => _retryingIndices.remove(index));
      }
    }
  }

  Future<void> _clearHistory() async {
    await _historyService.clear();
    if (!mounted) return;
    setState(() => _history.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: widget.bottomPadding),
          child: Stack(
          children: [
            Column(
              children: [
                const ModuleHeader(
                  title: 'Sign Language Translation',
                  accent: Color(0xFF9333EA),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: SignLanguageCameraCard(
                      label: 'Show hand signs to camera',
                      accent: const Color(0xFF3B82F6),
                      onPrediction: (rawLabel, confidence, allLetters) {
                        final isNewCaptureStart =
                            _allLetters.isEmpty && allLetters.isNotEmpty;
                        setState(() {
                          _allLetters = allLetters;
                          if (isNewCaptureStart) {
                            _meaning = '';
                          }
                        });
                        debugPrint(
                          'RAW: $rawLabel ${confidence.toStringAsFixed(1)}% | RESULT: $allLetters',
                        );
                      },
                      onFinalized: (capturedLetters, guessedText, trigger) async {
                        if (guessedText != null && guessedText.isNotEmpty) {
                          AppAnnouncer.instance.speak(guessedText);
                        }

                        await _saveTranslation(
                          capturedLetters: capturedLetters,
                          guessedText: guessedText,
                        );

                        debugPrint(
                          'FINALIZE($trigger): "$capturedLetters" -> "${guessedText ?? '(pending)'}"',
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: ModuleBottomSheet.collapsedHeight),
              ],
            ),
            ModuleBottomSheet(
              title: 'Translation History',
              accent: const Color(0xFFE9D5FF),
              hasData: _history.isNotEmpty || _allLetters.isNotEmpty || _meaning.isNotEmpty,
              child: _history.isEmpty && _allLetters.isEmpty && _meaning.isEmpty
                  ? const Text(
                      'Waiting for hand signs...',
                      style: TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 14,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_history.isNotEmpty)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: _clearHistory,
                              icon: const Icon(Icons.delete_outline, size: 16),
                              label: const Text('Clear All', style: TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.grey.shade600,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _history.isEmpty ? 1 : _history.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            if (_history.isEmpty) {
                              return Text(
                                _allLetters.isNotEmpty
                                    ? '$_allLetters${_meaning.isEmpty ? '' : '\nMeaning: $_meaning'}'
                                    : 'Meaning: $_meaning',
                                style: const TextStyle(
                                  color: Color(0xFF1F2937),
                                  fontSize: 14,
                                ),
                              );
                            }

                            final entry = _history[index];
                            final isPending = entry.meaning.isEmpty ||
                                entry.meaning == 'Pending translation';
                            final isRetrying = _retryingIndices.contains(index);

                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAF5FF),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isPending
                                      ? Colors.orange.shade200
                                      : const Color(0xFFE9D5FF),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        entry.text,
                                        style: const TextStyle(
                                          color: Color(0xFF1F2937),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                      if (isPending)
                                        isRetrying
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : InkWell(
                                                onTap: () => _retryTranslation(index, entry),
                                                borderRadius: BorderRadius.circular(6),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF9333EA).withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.refresh_rounded,
                                                        size: 14,
                                                        color: Color(0xFF9333EA),
                                                      ),
                                                      SizedBox(width: 4),
                                                      Text(
                                                        'Retry',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                          color: Color(0xFF9333EA),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isPending ? 'Pending translation' : entry.meaning,
                                    style: TextStyle(
                                      color: isPending
                                          ? Colors.orange.shade800
                                          : const Color(0xFF4B5563),
                                      fontSize: 14,
                                      fontStyle: isPending
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    ),
  );
  }
}
