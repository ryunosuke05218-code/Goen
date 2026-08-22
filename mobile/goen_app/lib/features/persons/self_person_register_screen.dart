import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/person_models.dart';
import 'occupation_picker.dart';
import 'person_repository.dart';
import 'sns_links_editor.dart';

/// 自分自身の人物カルテを新規登録する画面。[PersonEditScreen]と同じ項目構成の簡易フォームで、
/// 紹介者選択・音声入力等の「他者を登録する」ための機能は持たない。
/// 登録後は`isSelf: true`のPersonとして作成され、人物一覧では通常の登録人物と区別して最上部に固定表示される。
class SelfPersonRegisterScreen extends ConsumerStatefulWidget {
  const SelfPersonRegisterScreen({super.key, this.initialFullName});

  final String? initialFullName;

  @override
  ConsumerState<SelfPersonRegisterScreen> createState() => _SelfPersonRegisterScreenState();
}

class _SelfPersonRegisterScreenState extends ConsumerState<SelfPersonRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _fullName = TextEditingController(text: widget.initialFullName ?? '');
  final _fullNameKana = TextEditingController();
  final _companyName = TextEditingController();
  final _department = TextEditingController();
  final _jobTitle = TextEditingController();
  final _industryName = TextEditingController();
  final _occupationName = TextEditingController();
  final _tel = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _note = TextEditingController();
  List<SnsLink> _snsLinks = const [];
  bool _isSubmitting = false;

  @override
  void dispose() {
    for (final c in [
      _fullName, _fullNameKana, _companyName, _department, _jobTitle,
      _industryName, _occupationName, _tel, _mobile, _email, _address, _note,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _emptyToNull(String v) => v.trim().isEmpty ? null : v.trim();

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final person = await ref.read(personRepositoryProvider).create(
            fullName: _fullName.text.trim(),
            fullNameKana: _emptyToNull(_fullNameKana.text),
            department: _emptyToNull(_department.text),
            jobTitle: _emptyToNull(_jobTitle.text),
            occupationName: _emptyToNull(_occupationName.text),
            industryName: _emptyToNull(_industryName.text),
            companyName: _emptyToNull(_companyName.text),
            tel: _emptyToNull(_tel.text),
            mobile: _emptyToNull(_mobile.text),
            email: _emptyToNull(_email.text),
            address: _emptyToNull(_address.text),
            note: _emptyToNull(_note.text),
            snsLinks: _snsLinks,
            isSelf: true,
          );
      if (!mounted) return;
      Navigator.of(context).pop(person);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('登録に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自分の人物カルテを登録')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '自分自身のプロフィールを登録します。AI要約・AI指示・紹介文作成では、'
              '通常の登録人物とは区別され、人物一覧では常に最上部に表示されます（総登録人数には含まれません）。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
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
              decoration: const InputDecoration(labelText: '会社名', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _department,
              decoration: const InputDecoration(labelText: '部署', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _jobTitle,
              decoration: const InputDecoration(labelText: '役職', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            IndustryComboBox(controller: _industryName),
            const SizedBox(height: 12),
            OccupationComboBox(controller: _occupationName),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tel,
              decoration: const InputDecoration(labelText: '電話番号', border: OutlineInputBorder()),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mobile,
              decoration: const InputDecoration(labelText: '携帯番号', border: OutlineInputBorder()),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'メールアドレス', border: OutlineInputBorder()),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: '住所', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'メモ',
                border: OutlineInputBorder(),
                helperText: 'AI指示のRAG検索で拾えるようになります',
                alignLabelWithHint: true,
              ),
              minLines: 3,
              maxLines: 8,
            ),
            const SizedBox(height: 16),
            SnsLinksEditor(
              initialLinks: _snsLinks,
              onChanged: (links) => _snsLinks = links,
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
