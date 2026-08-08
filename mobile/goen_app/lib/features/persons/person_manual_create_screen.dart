import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/voice_input_field.dart';
import 'models/person_models.dart';
import 'occupation_picker.dart';
import 'person_picker.dart';
import 'person_repository.dart';
import 'sns_links_editor.dart';

/// F-002 人脈データ登録（手入力）
/// [PersonRegisterScreen] の「手入力で登録」タブに埋め込まれるため、Scaffold/AppBarは持たない。
class PersonManualCreateScreen extends ConsumerStatefulWidget {
  const PersonManualCreateScreen({super.key});

  @override
  ConsumerState<PersonManualCreateScreen> createState() =>
      _PersonManualCreateScreenState();
}

class _PersonManualCreateScreenState
    extends ConsumerState<PersonManualCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _fullNameKana = TextEditingController();
  final _companyName = TextEditingController();
  final _jobTitle = TextEditingController();
  final _email = TextEditingController();
  final _mobile = TextEditingController();
  final _note = TextEditingController();
  final _metPlace = TextEditingController();
  final _voiceDraftText = TextEditingController();
  String? _occupationCode;
  bool _isSubmitting = false;
  bool _isApplyingVoiceDraft = false;
  PersonListItem? _introducer;
  List<SnsLink> _snsLinks = const [];

  @override
  void dispose() {
    for (final c in [
      _fullName,
      _fullNameKana,
      _companyName,
      _jobTitle,
      _email,
      _mobile,
      _note,
      _metPlace,
      _voiceDraftText,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickIntroducer() async {
    final picked = await pickPerson(context, title: '紹介者を選択');
    if (picked != null) setState(() => _introducer = picked);
  }

  // F-002: 音声（文字起こし）を、名刺なしでもAIがそのまま各登録項目・メモに振り分ける
  Future<void> _applyVoiceDraft() async {
    if (_voiceDraftText.text.trim().isEmpty) return;
    setState(() => _isApplyingVoiceDraft = true);
    try {
      final draft = await ref
          .read(personRepositoryProvider)
          .voiceDraft(_voiceDraftText.text.trim());
      if (!mounted) return;
      setState(() {
        if (draft.fullName != null) _fullName.text = draft.fullName!;
        if (draft.fullNameKana != null) {
          _fullNameKana.text = draft.fullNameKana!;
        }
        if (draft.companyName != null) _companyName.text = draft.companyName!;
        if (draft.jobTitle != null) _jobTitle.text = draft.jobTitle!;
        if (draft.email != null) _email.text = draft.email!;
        if (draft.mobile != null) _mobile.text = draft.mobile!;
        if (draft.metPlace != null) _metPlace.text = draft.metPlace!;
        if (draft.note != null) {
          _note.text = _note.text.trim().isEmpty
              ? draft.note!
              : '${_note.text.trim()}\n${draft.note}';
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AIが各項目に振り分けました。内容を確認してください。')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('AIへの反映に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _isApplyingVoiceDraft = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final person = await ref
          .read(personRepositoryProvider)
          .create(
            fullName: _fullName.text.trim(),
            fullNameKana: _emptyToNull(_fullNameKana.text),
            companyName: _emptyToNull(_companyName.text),
            jobTitle: _emptyToNull(_jobTitle.text),
            occupationCode: _occupationCode,
            email: _emptyToNull(_email.text),
            mobile: _emptyToNull(_mobile.text),
            note: _emptyToNull(_note.text),
            metPlace: _emptyToNull(_metPlace.text),
            snsLinks: _snsLinks,
            introducerPersonId: _introducer?.personId,
          );
      if (!mounted) return;
      context.pushReplacement('/persons/${person.personId}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('登録に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _emptyToNull(String v) => v.trim().isEmpty ? null : v.trim();

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '音声でまとめて入力（任意）',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'マイクボタンで話すか直接テキストで入力し、「AIに反映」を押すと、氏名・会社名・連絡先などの下の項目やメモにAIが自動で振り分けます',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  VoiceInputField(
                    controller: _voiceDraftText,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '話した内容（音声 or テキスト）',
                      border: OutlineInputBorder(),
                      hintText: '例：田中さんはABC商事の営業部長で、〇〇交流会で知り合った。紹介者は佐藤さん。',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: _isApplyingVoiceDraft
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome_outlined),
                      label: Text(
                        _isApplyingVoiceDraft ? 'AIが振り分け中…' : 'AIに反映',
                      ),
                      onPressed: _isApplyingVoiceDraft
                          ? null
                          : _applyVoiceDraft,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _fullName,
            decoration: const InputDecoration(
              labelText: '氏名 *',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? '氏名を入力してください' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _fullNameKana,
            decoration: const InputDecoration(
              labelText: '氏名カナ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _companyName,
            decoration: const InputDecoration(
              labelText: '会社名',
              border: OutlineInputBorder(),
              helperText: '同じ会社の登録済み人物がいる場合、カルテのメモに自動で書き添えられます',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _jobTitle,
            decoration: const InputDecoration(
              labelText: '役職',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OccupationDropdown(
            value: _occupationCode,
            onChanged: (v) => setState(() => _occupationCode = v),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            decoration: const InputDecoration(
              labelText: 'メールアドレス',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _mobile,
            decoration: const InputDecoration(
              labelText: '携帯番号',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          TextFormField(
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
          const SizedBox(height: 12),
          TextFormField(
            controller: _metPlace,
            decoration: const InputDecoration(
              labelText: 'どこで会ったか',
              border: OutlineInputBorder(),
              hintText: '例：〇〇異業種交流会',
            ),
          ),
          const SizedBox(height: 16),
          SnsLinksEditor(
            initialLinks: _snsLinks,
            onChanged: (links) => _snsLinks = links,
          ),
          const SizedBox(height: 12),
          Text('紹介者（任意）', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          const Text(
            '選択すると人脈グラフに「紹介者」関係が自動的に登録されます（AI不使用）',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          if (_introducer case final introducer?)
            Card(
              child: ListTile(
                title: Text(introducer.fullName),
                subtitle: Text(introducer.companyName ?? ''),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _introducer = null),
                ),
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
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('登録する'),
          ),
        ],
      ),
    );
  }
}
