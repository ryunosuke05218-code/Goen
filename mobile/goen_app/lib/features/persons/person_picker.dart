import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/person_models.dart';
import 'person_repository.dart';

/// 登録済み人物を検索して1件選ぶための共通ボトムシート。
/// 紹介者の選択（F-005 AIを使わない自動生成）・人脈関係の手動登録などで共用する。
Future<PersonListItem?> pickPerson(
  BuildContext context, {
  String? excludePersonId,
  String title = '人物を選択',
}) {
  return showModalBottomSheet<PersonListItem>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _PersonPickerSheet(excludePersonId: excludePersonId, title: title),
  );
}

class _PersonPickerSheet extends ConsumerStatefulWidget {
  const _PersonPickerSheet({this.excludePersonId, required this.title});

  final String? excludePersonId;
  final String title;

  @override
  ConsumerState<_PersonPickerSheet> createState() => _PersonPickerSheetState();
}

class _PersonPickerSheetState extends ConsumerState<_PersonPickerSheet> {
  final _controller = TextEditingController();
  List<PersonListItem> _results = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() => _isLoading = true);
    try {
      final results = await ref.read(personRepositoryProvider).list(query: query.isEmpty ? null : query);
      if (!mounted) return;
      setState(() {
        _results = results.where((p) => p.personId != widget.excludePersonId).toList();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '氏名・会社名で検索',
                border: OutlineInputBorder(),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            if (_isLoading) const LinearProgressIndicator(),
            Expanded(
              child: _results.isEmpty && !_isLoading
                  ? const Center(child: Text('該当する人物がいません'))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final p = _results[index];
                        return ListTile(
                          title: Text(p.fullName),
                          subtitle: Text(p.companyName ?? ''),
                          onTap: () => Navigator.of(context).pop(p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
