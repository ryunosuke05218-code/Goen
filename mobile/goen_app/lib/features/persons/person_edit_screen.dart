import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/person_models.dart';
import 'person_repository.dart';

const _visibilityOptions = ['private', 'team', 'org'];

String _visibilityLabel(String v) => switch (v) {
      'private' => '非公開（自分のみ）',
      'team' => 'チームに公開',
      'org' => '組織全体に公開',
      _ => v,
    };

/// F-002/F-003 人脈データ登録・編集機能: 人物カルテの基本情報を手動で編集する画面。
class PersonEditScreen extends ConsumerStatefulWidget {
  const PersonEditScreen({super.key, required this.person});

  final PersonDetail person;

  @override
  ConsumerState<PersonEditScreen> createState() => _PersonEditScreenState();
}

class _PersonEditScreenState extends ConsumerState<PersonEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _fullName = TextEditingController(text: widget.person.fullName);
  late final _fullNameKana = TextEditingController(text: widget.person.fullNameKana);
  late final _companyName = TextEditingController(text: widget.person.companyName);
  late final _department = TextEditingController(text: widget.person.department);
  late final _jobTitle = TextEditingController(text: widget.person.jobTitle);
  late final _tel = TextEditingController(text: widget.person.tel);
  late final _mobile = TextEditingController(text: widget.person.mobile);
  late final _email = TextEditingController(text: widget.person.email);
  late final _address = TextEditingController(text: widget.person.address);
  late final _note = TextEditingController(text: widget.person.note);
  late int _importance = widget.person.importance;
  late bool _importanceIsManual = widget.person.importanceIsManual;
  late String _visibility = widget.person.visibility;
  bool _isSubmitting = false;

  @override
  void dispose() {
    for (final c in [
      _fullName, _fullNameKana, _companyName, _department, _jobTitle,
      _tel, _mobile, _email, _address, _note,
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
      await ref.read(personRepositoryProvider).update(
            personId: widget.person.personId,
            fullName: _fullName.text.trim(),
            fullNameKana: _emptyToNull(_fullNameKana.text),
            companyName: _emptyToNull(_companyName.text),
            department: _emptyToNull(_department.text),
            jobTitle: _emptyToNull(_jobTitle.text),
            importance: _importance,
            importanceIsManual: _importanceIsManual,
            visibility: _visibility,
            tel: _emptyToNull(_tel.text),
            mobile: _emptyToNull(_mobile.text),
            email: _emptyToNull(_email.text),
            address: _emptyToNull(_address.text),
            note: _emptyToNull(_note.text),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('人物カルテを編集')),
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
              controller: _department,
              decoration: const InputDecoration(labelText: '部署', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _jobTitle,
              decoration: const InputDecoration(labelText: '役職', border: OutlineInputBorder()),
            ),
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
                helperText: '同僚・取引先などの文脈情報もここに記録するとAI指示のRAG検索で拾えるようになります',
                alignLabelWithHint: true,
              ),
              minLines: 3,
              maxLines: 8,
            ),
            const Divider(height: 32),
            Text('重要度', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    icon: Icon(i <= _importance ? Icons.star : Icons.star_border, color: Colors.amber),
                    onPressed: () => setState(() {
                      _importance = i;
                      _importanceIsManual = true;
                    }),
                  ),
                const SizedBox(width: 8),
                Text('$_importance / 5'),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('重要度を手動固定する'),
              subtitle: const Text('ONにすると、以後のAI自動算出で上書きされなくなります（F-022）'),
              value: _importanceIsManual,
              onChanged: (v) => setState(() => _importanceIsManual = v),
            ),
            const Divider(height: 32),
            Text('公開範囲', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in _visibilityOptions)
                  ChoiceChip(
                    label: Text(_visibilityLabel(v)),
                    selected: _visibility == v,
                    onSelected: (_) => setState(() => _visibility = v),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('保存する'),
            ),
          ],
        ),
      ),
    );
  }
}
