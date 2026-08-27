import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models/person_models.dart';
import 'occupation_picker.dart';
import 'person_picker.dart';
import 'person_repository.dart';
import 'sns_links_editor.dart';

const _visibilityOptions = ['private', 'team', 'org'];

String _visibilityLabel(String v) => switch (v) {
      'private' => '非公開（自分のみ）',
      'team' => 'チームに公開',
      'org' => '組織全体に公開',
      _ => v,
    };

/// F-002/F-003 人脈データ登録・編集機能: 人物カルテの基本情報を手動で編集する画面。
class PersonEditScreen extends ConsumerStatefulWidget {
  const PersonEditScreen({super.key, required this.person, this.returnPath});

  final PersonDetail person;
  // 戻るボタンで明示的に戻したい遷移元（例: ダッシュボードの'/home?tab=0'）。未指定時は通常のpop()に任せる。
  final String? returnPath;

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
  late final _industryName = TextEditingController(text: widget.person.industryName);
  late final _occupationName = TextEditingController(text: widget.person.occupationName);
  late final _tel = TextEditingController(text: widget.person.tel);
  late final _mobile = TextEditingController(text: widget.person.mobile);
  late final _email = TextEditingController(text: widget.person.email);
  late final _address = TextEditingController(text: widget.person.address);
  late final _note = TextEditingController(text: widget.person.note);
  late final _metPlace = TextEditingController(text: widget.person.metPlace);
  late String _visibility = widget.person.visibility;
  late List<SnsLink> _snsLinks = widget.person.snsLinks;
  late String? _introducerPersonId = widget.person.introducerPersonId;
  late String? _introducerPersonName = widget.person.introducerPersonName;
  bool _isSubmitting = false;

  @override
  void dispose() {
    for (final c in [
      _fullName, _fullNameKana, _companyName, _department, _jobTitle,
      _industryName, _occupationName,
      _tel, _mobile, _email, _address, _note, _metPlace,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _emptyToNull(String v) => v.trim().isEmpty ? null : v.trim();

  Future<void> _pickIntroducer() async {
    final picked = await pickPerson(context, title: '紹介者を選択', excludePersonId: widget.person.personId);
    if (picked != null) {
      setState(() {
        _introducerPersonId = picked.personId;
        _introducerPersonName = picked.fullName;
      });
    }
  }

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
            occupationName: _emptyToNull(_occupationName.text),
            industryName: _emptyToNull(_industryName.text),
            visibility: _visibility,
            tel: _emptyToNull(_tel.text),
            mobile: _emptyToNull(_mobile.text),
            email: _emptyToNull(_email.text),
            address: _emptyToNull(_address.text),
            note: _emptyToNull(_note.text),
            metPlace: _emptyToNull(_metPlace.text),
            snsLinks: _snsLinks,
            introducerPersonId: _introducerPersonId,
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
      appBar: AppBar(
        leading: widget.returnPath == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '戻る',
                onPressed: () => context.go(widget.returnPath!),
              ),
        title: const Text('人物カルテを編集'),
      ),
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
            IndustryOccupationFields(industryController: _industryName, occupationController: _occupationName),
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
            const SizedBox(height: 16),
            Text('紹介者', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_introducerPersonName case final name?)
              Card(
                child: ListTile(
                  title: Text(name),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _introducerPersonId = null;
                      _introducerPersonName = null;
                    }),
                  ),
                ),
              )
            else
              OutlinedButton.icon(
                icon: const Icon(Icons.person_search_outlined),
                label: const Text('紹介者を選択'),
                onPressed: _pickIntroducer,
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
