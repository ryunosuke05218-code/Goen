import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../persons/models/person_models.dart';
import 'master_providers.dart';
import 'master_repository.dart';

/// F-030: 人物登録・編集画面から呼び出す職種追加シート。
/// 職種名に加え、紐づく業種を固定の業種一覧から複数選択できる（業種は固定8種のため新規作成は不可）。
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
  final Set<String> _industryCodes = {};
  bool _isSubmitting = false;

  @override
  void dispose() {
    _occupationName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final created = await ref.read(masterRepositoryProvider).createOccupationType(
            occupationName: _occupationName.text.trim(),
            industryCodes: _industryCodes.toList(),
          );
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
              const SizedBox(height: 16),
              Text('業種（任意・複数選択可）', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 4),
              industriesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (err, st) => const Text('業種一覧の取得に失敗しました', style: TextStyle(color: Colors.grey)),
                data: (industries) {
                  final active = industries.where((i) => i.isActive).toList();
                  return Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final i in active)
                        FilterChip(
                          label: Text(i.industryName),
                          selected: _industryCodes.contains(i.industryCode),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _industryCodes.add(i.industryCode);
                            } else {
                              _industryCodes.remove(i.industryCode);
                            }
                          }),
                        ),
                    ],
                  );
                },
              ),
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
