import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../persons/models/person_models.dart';
import 'master_providers.dart';
import 'master_repository.dart';

const _newIndustrySentinel = '__new__';

/// F-030: 人物登録・編集画面から呼び出す職種追加シート。
/// 職種名に加え、業種を既存から選択するか、その場で新規作成して紐付けられる。
/// 成功した場合、作成された職種を返す（キャンセル時はnull）。
Future<OccupationTypeItem?> showAddOccupationSheet(BuildContext context) {
  return showModalBottomSheet<OccupationTypeItem>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _OccupationAddSheet(),
  );
}

class _OccupationAddSheet extends ConsumerStatefulWidget {
  const _OccupationAddSheet();

  @override
  ConsumerState<_OccupationAddSheet> createState() => _OccupationAddSheetState();
}

class _OccupationAddSheetState extends ConsumerState<_OccupationAddSheet> {
  final _formKey = GlobalKey<FormState>();
  final _occupationName = TextEditingController();
  final _newIndustryName = TextEditingController();
  String? _industryCode;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _occupationName.dispose();
    _newIndustryName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final created = await ref.read(masterRepositoryProvider).createOccupationType(
            occupationName: _occupationName.text.trim(),
            industryCode: _industryCode == _newIndustrySentinel ? null : _industryCode,
            newIndustryName: _industryCode == _newIndustrySentinel ? _newIndustryName.text.trim() : null,
          );
      ref.invalidate(industriesProvider);
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('職種の追加に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final industriesAsync = ref.watch(industriesProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('職種を追加', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextFormField(
                controller: _occupationName,
                decoration: const InputDecoration(labelText: '職種名 *', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? '職種名を入力してください' : null,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              industriesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (err, st) => const Text('業種一覧の取得に失敗しました', style: TextStyle(color: Colors.grey)),
                data: (industries) {
                  final active = industries.where((i) => i.isActive).toList();
                  return DropdownButtonFormField<String>(
                    initialValue: _industryCode,
                    decoration: const InputDecoration(
                      labelText: '業種（任意）',
                      border: OutlineInputBorder(),
                      helperText: '既存の業種から選ぶか、新しい業種をその場で作成できます',
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('未設定')),
                      for (final i in active) DropdownMenuItem(value: i.industryCode, child: Text(i.industryName)),
                      const DropdownMenuItem(value: _newIndustrySentinel, child: Text('＋ 新しい業種を作成')),
                    ],
                    onChanged: (v) => setState(() => _industryCode = v),
                  );
                },
              ),
              if (_industryCode == _newIndustrySentinel) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _newIndustryName,
                  decoration: const InputDecoration(labelText: '新しい業種名 *', border: OutlineInputBorder()),
                  validator: (v) => (_industryCode == _newIndustrySentinel && (v == null || v.trim().isEmpty))
                      ? '業種名を入力してください'
                      : null,
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('追加する'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
