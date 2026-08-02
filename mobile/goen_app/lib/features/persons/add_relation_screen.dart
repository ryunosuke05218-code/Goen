import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/person_models.dart';
import 'person_picker.dart';
import 'person_repository.dart';
import 'relation_type.dart';

const _relationTypes = ['referrer', 'community'];

/// F-005/F-006 人脈グラフの手動登録画面。AIの提案を経由せず、人物・関係種別・強さを
/// 自分で指定して直接登録できる（AIを使わない人脈グラフ作成のための導線）。
class AddRelationScreen extends ConsumerStatefulWidget {
  const AddRelationScreen({super.key, required this.personId});

  final String personId;

  @override
  ConsumerState<AddRelationScreen> createState() => _AddRelationScreenState();
}

class _AddRelationScreenState extends ConsumerState<AddRelationScreen> {
  PersonListItem? _selectedPerson;
  String _relationType = 'community';
  int _strength = 3;
  bool _isBidirectional = false;
  bool _isSubmitting = false;

  Future<void> _pickPerson() async {
    final picked = await pickPerson(context, excludePersonId: widget.personId, title: '相手を選択');
    if (picked != null) setState(() => _selectedPerson = picked);
  }

  Future<void> _submit() async {
    final target = _selectedPerson;
    if (target == null) return;

    setState(() => _isSubmitting = true);
    try {
      await ref.read(personRepositoryProvider).createRelation(
            personId: widget.personId,
            relatedPersonId: target.personId,
            relationType: _relationType,
            strength: _strength,
            isBidirectional: _isBidirectional,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
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
      appBar: AppBar(title: const Text('関係を手動で追加')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('1. 相手を選択', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_selectedPerson case final selected?)
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                title: Text(selected.fullName),
                subtitle: Text(selected.companyName ?? ''),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _selectedPerson = null),
                ),
                onTap: _pickPerson,
              ),
            )
          else
            OutlinedButton.icon(
              icon: const Icon(Icons.person_search_outlined),
              label: const Text('人物を検索して選択'),
              onPressed: _pickPerson,
            ),
          const Divider(height: 32),
          Text('2. 関係の種類', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in _relationTypes)
                ChoiceChip(
                  label: Text(RelationTypeStyle.label(type)),
                  selected: _relationType == type,
                  onSelected: (_) => setState(() => _relationType = type),
                ),
            ],
          ),
          const Divider(height: 32),
          Text('3. 関係の強さ', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  icon: Icon(i <= _strength ? Icons.star : Icons.star_border, color: Colors.amber),
                  onPressed: () => setState(() => _strength = i),
                ),
              const SizedBox(width: 8),
              Text('$_strength / 5'),
            ],
          ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('相互の関係として登録する'),
            subtitle: const Text('ONにすると相手側からも同じ関係が張られます'),
            value: _isBidirectional,
            onChanged: (v) => setState(() => _isBidirectional = v),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: (_selectedPerson == null || _isSubmitting) ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('この関係を登録する'),
          ),
        ],
      ),
    );
  }
}
