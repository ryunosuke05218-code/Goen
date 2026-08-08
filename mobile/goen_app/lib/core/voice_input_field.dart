import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// F-007/F-009 音声入力欄。OS標準の音声認識（Android/iOSネイティブ機能）でその場文字起こしする。
/// マイクボタンで開始・停止し、認識結果を [controller] に追記していく。
/// 端末が音声認識に対応していない場合は、通常のテキスト入力にフォールバックする。
class VoiceInputField extends StatefulWidget {
  const VoiceInputField({
    super.key,
    required this.controller,
    this.decoration,
    this.minLines,
    this.maxLines,
  });

  final TextEditingController controller;
  final InputDecoration? decoration;
  final int? minLines;
  final int? maxLines;

  @override
  State<VoiceInputField> createState() => _VoiceInputFieldState();
}

class _VoiceInputFieldState extends State<VoiceInputField> {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  bool _listening = false;
  String _baseText = '';

  @override
  void dispose() {
    if (_listening) _speech.stop();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    if (!_initialized) {
      final available = await _speech.initialize();
      if (!mounted) return;
      if (!available) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('この端末では音声入力が利用できません。テキストで入力してください。')));
        return;
      }
      _initialized = true;
    }

    _baseText = widget.controller.text;
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        final separator = _baseText.isEmpty || result.recognizedWords.isEmpty ? '' : ' ';
        widget.controller.text = '$_baseText$separator${result.recognizedWords}';
        widget.controller.selection = TextSelection.collapsed(offset: widget.controller.text.length);
      },
      listenOptions: SpeechListenOptions(localeId: 'ja_JP'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseDecoration = widget.decoration ?? const InputDecoration();
    return TextField(
      controller: widget.controller,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      decoration: baseDecoration.copyWith(
        suffixIcon: IconButton(
          icon: Icon(_listening ? Icons.mic : Icons.mic_none),
          color: _listening ? Theme.of(context).colorScheme.error : null,
          tooltip: _listening ? '音声入力を停止' : '音声入力を開始',
          onPressed: _toggle,
        ),
        helperText: _listening ? '聞き取り中…話し終えたらマイクボタンをタップして停止してください' : baseDecoration.helperText,
      ),
    );
  }
}
