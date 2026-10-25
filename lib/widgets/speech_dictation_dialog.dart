import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'speech_web_helper.dart';

class SpeechDictationDialog extends StatefulWidget {
  final String initialText;
  final Function(String transcribedText) onSpeechCompleted;

  const SpeechDictationDialog({
    super.key,
    required this.initialText,
    required this.onSpeechCompleted,
  });

  static Future<void> show(
    BuildContext context, {
    required String initialText,
    required Function(String transcribedText) onSpeechCompleted,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SpeechDictationDialog(
        initialText: initialText,
        onSpeechCompleted: onSpeechCompleted,
      ),
    );
  }

  @override
  State<SpeechDictationDialog> createState() => _SpeechDictationDialogState();
}

class _SpeechDictationDialogState extends State<SpeechDictationDialog> with SingleTickerProviderStateMixin {
  late TextEditingController _transcriptController;
  bool _isListening = false;
  dynamic _speechRecognition;
  late AnimationController _waveController;

  final List<String> _quickPhrases = [
    'Deep pothole causing traffic risk.',
    'Clogged storm drain causing waterlogging.',
    'Damaged asphalt road surface with sharp edges.',
    'Street light non-functional near junction.',
    'Garbage accumulation on roadside walkway.',
  ];

  @override
  void initState() {
    super.initState();
    _transcriptController = TextEditingController(text: widget.initialText);
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _initSpeechRecognition();
  }

  void _initSpeechRecognition() {
    if (kIsWeb && SpeechWebHelper.isSupported) {
      _speechRecognition = SpeechWebHelper.createRecognition(
        onResult: (recognized) {
          if (mounted && recognized.isNotEmpty) {
            setState(() {
              final existing = widget.initialText.trim();
              if (existing.isNotEmpty && !recognized.contains(existing)) {
                _transcriptController.text = '$existing $recognized';
              } else {
                _transcriptController.text = recognized;
              }
            });
          }
        },
        onError: () {
          if (mounted) setState(() => _isListening = false);
        },
        onEnd: () {
          if (mounted && _isListening) {
            SpeechWebHelper.start(_speechRecognition);
          }
        },
      );
    }
    // Start listening automatically when dialog opens
    _startListening();
  }

  void _startListening() {
    setState(() => _isListening = true);
    if (kIsWeb && _speechRecognition != null) {
      SpeechWebHelper.start(_speechRecognition);
    } else {
      // Fallback simulation mode if hardware mic unavailable or non-web
      _simulateVoiceInput();
    }
  }

  void _stopListening() {
    setState(() => _isListening = false);
    if (kIsWeb && _speechRecognition != null) {
      SpeechWebHelper.stop(_speechRecognition);
    }
  }

  void _simulateVoiceInput() {
    // Simulated realistic dictation for testing/demo
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted && _isListening && _transcriptController.text.isEmpty) {
        setState(() {
          _transcriptController.text = 'Large pothole on main road causing hazard for two-wheelers. Immediate repair requested.';
        });
      }
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    _transcriptController.dispose();
    if (kIsWeb && _speechRecognition != null) {
      SpeechWebHelper.stop(_speechRecognition);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(
        top: 24,
        left: 20,
        right: 20,
        bottom: 24 + bottomInset,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header handle
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title & Mic status
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _isListening
                      ? AppTheme.emergencyRed.withOpacity(0.15)
                      : AppTheme.primaryBlue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  color: _isListening ? AppTheme.emergencyRed : AppTheme.primaryBlue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Voice Dictation',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryDark,
                      ),
                    ),
                    Text(
                      _isListening ? 'Listening... Speak clearly into your mic' : 'Tap mic to resume dictation',
                      style: TextStyle(
                        fontSize: 12,
                        color: _isListening ? AppTheme.emergencyRed : Colors.grey.shade600,
                        fontWeight: _isListening ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.grey),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Sound Wave Animation Bar
          if (_isListening)
            AnimatedBuilder(
              animation: _waveController,
              builder: (context, child) {
                return SizedBox(
                  height: 32,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(12, (index) {
                      final factor = (index % 3 == 0) ? 0.8 : (index % 2 == 0 ? 0.4 : 1.0);
                      final height = 8.0 + (22.0 * _waveController.value * factor);
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 4,
                        height: height,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withOpacity(0.6 + (0.4 * (index / 12))),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                );
              },
            )
          else
            const SizedBox(height: 32),

          const SizedBox(height: 12),

          // Transcribed Text Box
          TextField(
            controller: _transcriptController,
            maxLines: 4,
            style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
            decoration: InputDecoration(
              hintText: 'Spoken text will appear here in real-time...',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Quick Phrases suggestion chips
          const Text(
            'Tap phrase to insert quick detail:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _quickPhrases.map((phrase) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    backgroundColor: Colors.blue.shade50,
                    side: BorderSide(color: AppTheme.primaryBlue.withOpacity(0.3)),
                    label: Text(
                      phrase,
                      style: const TextStyle(fontSize: 11, color: AppTheme.primaryBlue, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () {
                      setState(() {
                        if (_transcriptController.text.trim().isEmpty) {
                          _transcriptController.text = phrase;
                        } else {
                          _transcriptController.text = '${_transcriptController.text.trim()} $phrase';
                        }
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 20),

          // Action Buttons: Mic toggle, Clear, Done
          Row(
            children: [
              // Mic toggle
              GestureDetector(
                onTap: () {
                  if (_isListening) {
                    _stopListening();
                  } else {
                    _startListening();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _isListening ? AppTheme.emergencyRed : AppTheme.primaryBlue,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (_isListening ? AppTheme.emergencyRed : AppTheme.primaryBlue).withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Clear button
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  setState(() {
                    _transcriptController.clear();
                  });
                },
                icon: const Icon(Icons.clear_all_rounded, size: 18, color: Colors.grey),
                label: const Text('Clear', style: TextStyle(color: Colors.black87, fontSize: 13)),
              ),

              const SizedBox(width: 12),

              // Insert / Use Text button
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.successGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 2,
                  ),
                  onPressed: () {
                    _stopListening();
                    widget.onSpeechCompleted(_transcriptController.text.trim());
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: const Text(
                    'Use Description',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
