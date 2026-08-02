import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'models/person_models.dart';
import 'person_picker.dart';
import 'person_repository.dart';

/// S-003 名刺撮影画面（F-007）。撮影後、外部OCR APIへ送信し確認画面(S-004)へ遷移する。
class PersonCardCaptureScreen extends ConsumerStatefulWidget {
  const PersonCardCaptureScreen({super.key});

  @override
  ConsumerState<PersonCardCaptureScreen> createState() => _PersonCardCaptureScreenState();
}

class _PersonCardCaptureScreenState extends ConsumerState<PersonCardCaptureScreen> {
  File? _image;
  bool _isProcessing = false;
  bool _isDragging = false;
  String? _errorMessage;

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    setState(() {
      _image = File(picked.path);
      _errorMessage = null;
    });
  }

  // OSのファイル選択ダイアログから画像を選ぶ。Windows/macOS/Linuxではネイティブのファイル選択画面が開き、
  // ドラッグ＆ドロップ（デスクトップ限定）が使えない環境でも名刺画像を取り込める。
  // Android/iOSではシステムのドキュメントピッカーが開く（端末内のダウンロードフォルダ等も参照可能）。
  Future<void> _browseFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _image = File(path);
      _errorMessage = null;
    });
  }

  // 開発用: エミュレータ/シミュレータからはホストPCのファイルにアクセスできない（ドラッグ＆ドロップも
  // ホストOSの壁を越えられない）ため、動作確認用の名刺画像をアプリに同梱し、実機・エミュレータどちらでも
  // 同じ手順で名刺OCRを試せるようにする。デバッグビルドでのみ表示する。
  Future<void> _loadTestAsset() async {
    try {
      final bytes = await rootBundle.load('assets/test_data/test_nameplete1.png');
      final file = File('${Directory.systemTemp.path}/test_nameplete1.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      setState(() {
        _image = file;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() => _errorMessage = 'テスト画像の読み込みに失敗しました: $e');
    }
  }

  static const _supportedImageExtensions = ['.jpg', '.jpeg', '.png', '.webp'];

  void _handleDroppedFiles(DropDoneDetails details) {
    if (details.files.isEmpty) return;
    final file = details.files.first;
    final ext = '.${file.path.split('.').last.toLowerCase()}';
    if (!_supportedImageExtensions.contains(ext)) {
      setState(() => _errorMessage = '画像ファイル（jpg/png/webp）をドロップしてください');
      return;
    }
    setState(() {
      _image = File(file.path);
      _errorMessage = null;
    });
  }

  Future<void> _runOcr() async {
    if (_image == null) return;
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    try {
      final draft = await ref.read(personRepositoryProvider).ocrDraft(_image!);
      if (!mounted) return;
      context.push('/persons/new/confirm', extra: draft);
    } catch (e) {
      setState(() => _errorMessage = 'OCR処理に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('名刺を撮影')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: DropTarget(
                onDragDone: _handleDroppedFiles,
                onDragEntered: (_) => setState(() => _isDragging = true),
                onDragExited: (_) => setState(() => _isDragging = false),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _isDragging ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                      width: _isDragging ? 2 : 1,
                    ),
                    color: _isDragging ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06) : null,
                  ),
                  child: _image == null
                      ? Center(
                          child: Text(
                            _isDragging ? 'ここに画像をドロップ' : '名刺を撮影・ギャラリーから選択、\n「ファイルを選択」またはドラッグ＆ドロップで読み込めます',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : Image.file(_image!, fit: BoxFit.contain),
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('撮影'),
                    onPressed: _isProcessing ? null : () => _pickImage(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('ギャラリー'),
                    onPressed: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('ファイルを選択'),
                onPressed: _isProcessing ? null : _browseFile,
              ),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.bug_report_outlined),
                  label: const Text('テスト画像を読み込む（開発用）'),
                  onPressed: _isProcessing ? null : _loadTestAsset,
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: (_image == null || _isProcessing) ? null : _runOcr,
              child: _isProcessing
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('この名刺を読み取る'),
            ),
            if (_isProcessing) ...[
              const SizedBox(height: 8),
              const Text(
                'AIが名刺を読み取っています…（ローカルAIのため1分ほどかかる場合があります）',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// S-004 登録内容確認画面。OCR抽出結果を確認・修正してから確定登録する。
class PersonRegisterConfirmScreen extends ConsumerStatefulWidget {
  const PersonRegisterConfirmScreen({super.key, required this.draft});

  final OcrDraft draft;

  @override
  ConsumerState<PersonRegisterConfirmScreen> createState() => _PersonRegisterConfirmScreenState();
}

class _PersonRegisterConfirmScreenState extends ConsumerState<PersonRegisterConfirmScreen> {
  late final TextEditingController _fullName = TextEditingController(text: widget.draft.fullName);
  late final TextEditingController _fullNameKana = TextEditingController(text: widget.draft.fullNameKana);
  late final TextEditingController _companyName = TextEditingController(text: widget.draft.companyName);
  late final TextEditingController _jobTitle = TextEditingController(text: widget.draft.jobTitle);
  late final TextEditingController _email = TextEditingController(text: widget.draft.email);
  late final TextEditingController _mobile = TextEditingController(text: widget.draft.mobile);
  final TextEditingController _note = TextEditingController();
  bool _isSubmitting = false;
  PersonListItem? _introducer;

  @override
  void dispose() {
    for (final c in [_fullName, _fullNameKana, _companyName, _jobTitle, _email, _mobile, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickIntroducer() async {
    final picked = await pickPerson(context, title: '紹介者を選択');
    if (picked != null) setState(() => _introducer = picked);
  }

  Future<void> _confirm() async {
    setState(() => _isSubmitting = true);
    try {
      final person = await ref.read(personRepositoryProvider).create(
            fullName: _fullName.text.trim(),
            fullNameKana: _emptyToNull(_fullNameKana.text),
            companyName: _emptyToNull(_companyName.text),
            jobTitle: _emptyToNull(_jobTitle.text),
            email: _emptyToNull(_email.text),
            mobile: _emptyToNull(_mobile.text),
            note: _emptyToNull(_note.text),
            sourceType: 'card_ocr',
            introducerPersonId: _introducer?.personId,
          );
      if (!mounted) return;
      // F-007事後条件: 登録後は続けて音声メモ入力(S-005)へ遷移する
      context.pushReplacement('/persons/${person.personId}/voice-memo');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('登録に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _emptyToNull(String v) => v.trim().isEmpty ? null : v.trim();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登録内容の確認')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Chip(label: Text('AI(OCR)による自動抽出結果です。内容を確認・修正してください。')),
          const SizedBox(height: 16),
          TextField(controller: _fullName, decoration: const InputDecoration(labelText: '氏名', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _fullNameKana, decoration: const InputDecoration(labelText: '氏名カナ', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _companyName, decoration: const InputDecoration(labelText: '会社名', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _jobTitle, decoration: const InputDecoration(labelText: '役職', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _email, decoration: const InputDecoration(labelText: 'メールアドレス', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _mobile, decoration: const InputDecoration(labelText: '携帯番号', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'メモ',
              border: OutlineInputBorder(),
              helperText: '同僚・取引先などの文脈情報もここに記録するとAI指示のRAG検索で拾えるようになります',
              alignLabelWithHint: true,
            ),
            minLines: 3,
            maxLines: 8,
          ),
          const SizedBox(height: 16),
          Text('紹介者（任意）', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          const Text('選択すると人脈グラフに「紹介者」関係が自動的に登録されます（AI不使用）', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          if (_introducer case final introducer?)
            Card(
              child: ListTile(
                title: Text(introducer.fullName),
                subtitle: Text(introducer.companyName ?? ''),
                trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _introducer = null)),
              ),
            )
          else
            OutlinedButton.icon(
              icon: const Icon(Icons.person_search_outlined),
              label: const Text('紹介者を選択'),
              onPressed: _pickIntroducer,
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isSubmitting ? null : _confirm,
            child: _isSubmitting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('この内容で登録する'),
          ),
        ],
      ),
    );
  }
}
