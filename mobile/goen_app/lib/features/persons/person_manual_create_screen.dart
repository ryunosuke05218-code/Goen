import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models/person_models.dart';
import 'person_picker.dart';
import 'person_repository.dart';

/// F-002 人脈データ登録（手入力）
class PersonManualCreateScreen extends ConsumerStatefulWidget {
  const PersonManualCreateScreen({super.key});

  @override
  ConsumerState<PersonManualCreateScreen> createState() => _PersonManualCreateScreenState();
}

class _PersonManualCreateScreenState extends ConsumerState<PersonManualCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _fullNameKana = TextEditingController();
  final _companyName = TextEditingController();
  final _jobTitle = TextEditingController();
  final _email = TextEditingController();
  final _mobile = TextEditingController();
  final _note = TextEditingController();
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
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
            introducerPersonId: _introducer?.personId,
          );
      if (!mounted) return;
      context.pushReplacement('/persons/${person.personId}');
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
      appBar: AppBar(title: const Text('人物を登録')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _fullName,
              decoration: const InputDecoration(labelText: '氏名 *', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? '氏名を入力してください' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fullNameKana,
              decoration: const InputDecoration(labelText: '氏名カナ', border: OutlineInputBorder()),
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
              decoration: const InputDecoration(labelText: '役職', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'メールアドレス', border: OutlineInputBorder()),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mobile,
              decoration: const InputDecoration(labelText: '携帯番号', border: OutlineInputBorder()),
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
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('登録する'),
            ),
          ],
        ),
      ),
    );
  }
}
