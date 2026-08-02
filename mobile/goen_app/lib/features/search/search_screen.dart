import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../persons/person_repository.dart';

/// S-008 検索画面（F-004）。
/// 本スキャフォールドでは persons_read への部分一致検索のみを実装する。
/// RAG（ベクトル検索＋全文検索のハイブリッド、テーブル設計書9.1）は将来のフェーズで拡張する。
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _queryController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  List<dynamic> _results = [];

  Future<void> _search() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await ref.read(personRepositoryProvider).list(query: _queryController.text.trim());
      setState(() => _results = results);
    } catch (e) {
      setState(() => _error = '検索に失敗しました: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('曖昧検索')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('氏名がわからなくても、課題・地域・時期などのキーワードで検索できます（簡易版）。'),
            const SizedBox(height: 12),
            TextField(
              controller: _queryController,
              decoration: InputDecoration(
                hintText: '例）動画制作 京都',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _search),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final p = _results[index];
                  return ListTile(
                    title: Text(p.fullName),
                    subtitle: Text(p.summary ?? p.companyName ?? ''),
                    onTap: () => context.push('/persons/${p.personId}'),
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
