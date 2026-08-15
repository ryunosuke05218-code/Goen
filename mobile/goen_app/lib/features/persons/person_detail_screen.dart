import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../home/main_bottom_nav_bar.dart';
import 'models/person_models.dart';
import 'person_network_screen.dart';
import 'person_repository.dart';
import 'relation_type.dart';

final personDetailProvider = FutureProvider.autoDispose.family<PersonDetail, String>((ref, personId) async {
  final repo = ref.watch(personRepositoryProvider);
  return repo.get(personId);
});

final personContactsProvider = FutureProvider.autoDispose.family<List<ContactItem>, String>((ref, personId) async {
  final repo = ref.watch(personRepositoryProvider);
  return repo.listContacts(personId);
});

// F-033: 情報充実度に応じた入力促進ヒント。閉じた人物IDの集合をアプリ再起動まで保持する（永続化はしない）
class _InfoHintDismissalNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void dismiss(String personId) => state = {...state, personId};
}

final _infoHintDismissedProvider = NotifierProvider<_InfoHintDismissalNotifier, Set<String>>(_InfoHintDismissalNotifier.new);

/// S-006 人物カルテ画面（F-010 AI要約・F-011 接点履歴タイムライン）
class PersonDetailScreen extends ConsumerWidget {
  const PersonDetailScreen({super.key, required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(personDetailProvider(personId));
    final contactsAsync = ref.watch(personContactsProvider(personId));
    final networkAsync = ref.watch(personNetworkGraphProvider(personId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('人物カルテ'),
        actions: [
          if (detailAsync.value case final person?)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'カルテを編集',
              onPressed: () async {
                final updated = await context.push<bool>('/persons/$personId/edit', extra: person);
                if (updated == true) {
                  ref.invalidate(personDetailProvider(personId));
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.hub_outlined),
            tooltip: '人脈グラフを見る',
            onPressed: () => context.push('/persons/$personId/network'),
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(child: Text('読み込みに失敗しました: $err')),
        data: (person) {
          final hasNotes = (contactsAsync.value ?? const [])
              .any((c) => (c.note ?? '').trim().isNotEmpty);
          return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(personDetailProvider(personId));
            ref.invalidate(personContactsProvider(personId));
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(person.fullName, style: Theme.of(context).textTheme.headlineSmall),
              if (person.fullNameKana != null) Text(person.fullNameKana!, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text([person.companyName, person.department, person.jobTitle]
                  .whereType<String>()
                  .where((e) => e.isNotEmpty)
                  .join(' / ')),
              if (person.occupationName != null)
                Text('職種: ${person.occupationName}', style: Theme.of(context).textTheme.bodySmall),
              if (person.introducerPersonName != null) ...[
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => context.push('/persons/${person.introducerPersonId}'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_search_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 4),
                      Text('紹介者: ${person.introducerPersonName}', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                    ],
                  ),
                ),
              ],
              if (person.metPlace != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.place_outlined, size: 16, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 4),
                    Text('どこで会ったか: ${person.metPlace}'),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              if (person.aiSummary == null && !hasNotes)
                _InfoRichnessHint(personId: personId),
              _SectionCard(
                title: 'AI要約',
                trailing: person.aiSummary == null
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Chip(label: Text('AI生成'), visualDensity: VisualDensity.compact),
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            tooltip: 'AI要約を更新する',
                            onPressed: () => _showGenerateCardSheet(context, ref, personId),
                          ),
                        ],
                      ),
                child: person.aiSummary == null
                    ? FilledButton.tonal(
                        onPressed: () => _showGenerateCardSheet(context, ref, personId),
                        child: const Text('AIカルテを生成する（F-010）'),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(person.aiSummary!),
                          _AiSummarySources(person: person),
                        ],
                      ),
              ),
              if (person.aiBusiness != null) _SectionCard(title: '事業内容', child: Text(person.aiBusiness!)),
              if (person.aiIssues != null) _SectionCard(title: '抱える課題', child: Text(person.aiIssues!)),
              if (person.aiHobby != null) _SectionCard(title: '趣味・人柄', child: Text(person.aiHobby!)),
              _SectionCard(
                title: '連絡先',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (person.tel != null) Text('TEL: ${person.tel}'),
                    if (person.mobile != null) Text('携帯: ${person.mobile}'),
                    if (person.email != null) Text('Email: ${person.email}'),
                    if (person.address != null) Text('住所: ${person.address}'),
                  ],
                ),
              ),
              if (person.snsLinks.isNotEmpty)
                _SectionCard(
                  title: 'SNSリンク',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final link in person.snsLinks)
                        ActionChip(
                          avatar: const Icon(Icons.link, size: 16),
                          label: Text(link.label ?? link.url),
                          onPressed: () => _openLink(context, link.url),
                        ),
                    ],
                  ),
                ),
              _SectionCard(
                title: 'メモ',
                trailing: person.note == null
                    ? null
                    : const Tooltip(
                        message: 'AI指示のRAG検索で補足情報として参照されます',
                        child: Icon(Icons.auto_awesome_outlined, size: 16),
                      ),
                child: person.note == null
                    ? Text(
                        'まだメモが登録されていません。同僚・取引先などの文脈情報を書いておくと、AI指示のRAG検索で拾えるようになります。',
                        style: TextStyle(color: Theme.of(context).colorScheme.outline),
                      )
                    : Text(person.note!),
              ),
              _SectionCard(
                title: '人脈グラフ',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('他の登録済み人物との関係（紹介者・同僚など）を登録できます。AIを使わず自分で選んで登録することも、AIに提案してもらうこともできます。'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.add_link),
                          label: const Text('手動で関係を追加'),
                          onPressed: () async {
                            final added = await context.push<bool>('/persons/$personId/relations/new');
                            if (added == true) {
                              ref.invalidate(personNetworkGraphProvider(personId));
                            }
                          },
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.auto_awesome_outlined),
                          label: const Text('AIに関係性を提案してもらう'),
                          onPressed: () => _showRelationSuggestions(context, ref, personId),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Text('登録済みの関係', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    networkAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      ),
                      error: (err, st) => Text('取得に失敗しました: $err', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      data: (graph) {
                        final nodeById = {for (final n in graph.nodes) n.personId: n};
                        final related = graph.edges
                            .where((e) =>
                                e.relationType != 'self' && (e.fromPersonId == personId || e.toPersonId == personId))
                            .toList();
                        if (related.isEmpty) {
                          return const Text('まだ関係が登録されていません。', style: TextStyle(fontSize: 12, color: Colors.grey));
                        }
                        return Column(
                          children: [
                            for (final e in related)
                              if (nodeById[e.fromPersonId == personId ? e.toPersonId : e.fromPersonId] case final other?)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  leading: CircleAvatar(radius: 6, backgroundColor: RelationTypeStyle.color(e.relationType)),
                                  title: Text(other.fullName),
                                  subtitle: Text(RelationTypeStyle.label(e.relationType)),
                                  onTap: () => context.push('/persons/${other.personId}'),
                                ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('接点履歴', style: Theme.of(context).textTheme.titleMedium),
              contactsAsync.when(
                loading: () => const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
                error: (err, st) => Text('接点履歴の取得に失敗しました: $err'),
                data: (contacts) {
                  if (contacts.isEmpty) {
                    return const Padding(padding: EdgeInsets.all(8), child: Text('まだ接点が記録されていません'));
                  }
                  return Column(
                    children: contacts
                        .map((c) => ListTile(
                              leading: const Icon(Icons.event_note_outlined),
                              title: Text(_contactTypeLabel(c.contactType)),
                              subtitle: Text('${c.occurredAt.toLocal()}'.split('.').first + (c.place != null ? ' / ${c.place}' : '')),
                              trailing: c.note != null ? const Icon(Icons.notes, size: 18) : null,
                              onTap: () async {
                                await context.push(
                                  '/persons/$personId/contacts/${c.contactId}',
                                  extra: (c, person.fullName),
                                );
                                ref.invalidate(personContactsProvider(personId));
                              },
                            ))
                        .toList(),
                  );
                },
              ),
            ],
          ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('接点を記録'),
        onPressed: () async {
          final saved = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            builder: (_) => _ContactFormSheet(personId: personId),
          );
          if (saved == true) {
            ref.invalidate(personContactsProvider(personId));
            ref.invalidate(personDetailProvider(personId));
          }
        },
      ),
      bottomNavigationBar: const MainBottomNavBar(selectedIndex: 1),
    );
  }
}

// SNSリンクをタップしたときに既定のブラウザ・アプリで開く
Future<void> _openLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  final launched = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('リンクを開けませんでした: $url')));
  }
}

const _contactTypeOptions = ['one_on_one', 'meeting', 'card_exchange', 'referral', 'event', 'other'];

String _contactTypeLabel(String type) => switch (type) {
      'card_exchange' => '名刺交換',
      'one_on_one' => '1to1',
      'meeting' => '商談',
      'referral' => '紹介',
      'event' => 'イベント同席',
      _ => 'その他',
    };

// F-011 接点履歴の記録フォーム: 種別・場所・何を話したかのメモを入力してから登録する
class _ContactFormSheet extends ConsumerStatefulWidget {
  const _ContactFormSheet({required this.personId});

  final String personId;

  @override
  ConsumerState<_ContactFormSheet> createState() => _ContactFormSheetState();
}

class _ContactFormSheetState extends ConsumerState<_ContactFormSheet> {
  String _contactType = 'one_on_one';
  DateTime _occurredAt = DateTime.now();
  final _place = TextEditingController();
  final _note = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _place.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _occurredAt = DateTime(picked.year, picked.month, picked.day, _occurredAt.hour, _occurredAt.minute);
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_occurredAt));
    if (picked == null) return;
    setState(() {
      _occurredAt = DateTime(_occurredAt.year, _occurredAt.month, _occurredAt.day, picked.hour, picked.minute);
    });
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      await ref.read(personRepositoryProvider).addContact(
            personId: widget.personId,
            contactType: _contactType,
            occurredAt: _occurredAt,
            place: _place.text.trim().isEmpty ? null : _place.text.trim(),
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('記録に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('接点を記録', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in _contactTypeOptions)
                ChoiceChip(
                  label: Text(_contactTypeLabel(type)),
                  selected: _contactType == type,
                  onSelected: (_) => setState(() => _contactType = type),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(
                    '${_occurredAt.year}/${_twoDigits(_occurredAt.month)}/${_twoDigits(_occurredAt.day)}',
                  ),
                  onPressed: _pickDate,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.schedule_outlined, size: 18),
                  label: Text('${_twoDigits(_occurredAt.hour)}:${_twoDigits(_occurredAt.minute)}'),
                  onPressed: _pickTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _place,
            decoration: const InputDecoration(labelText: '場所（任意）', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'メモ',
              hintText: '何を話したか、次のアクションなどを残しておきましょう',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('記録する'),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                ?trailing,
              ],
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}

// F-033: 接点メモもAI要約もまだない人物カルテに、追加入力を促すヒントを表示する（非強制・閉じられる）
class _InfoRichnessHint extends ConsumerWidget {
  const _InfoRichnessHint({required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(_infoHintDismissedProvider).contains(personId);
    if (dismissed) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'HPリンクや接点メモを追加すると、AIがより詳しい要約や紹介文を作れるようになります',
                style: TextStyle(fontSize: 12),
              ),
            ),
            InkWell(
              onTap: () => ref.read(_infoHintDismissedProvider.notifier).dismiss(personId),
              child: const Icon(Icons.close, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}

// F-032: AI要約が生成時に参照したHPリンク・資料ファイル・接点メモ件数を表示する（根拠の可視化）
class _AiSummarySources extends StatelessWidget {
  const _AiSummarySources({required this.person});

  final PersonDetail person;

  @override
  Widget build(BuildContext context) {
    final hasUrls = person.aiSummarySourceUrls.isNotEmpty;
    final hasFiles = person.aiSummarySourceFiles.isNotEmpty;
    final hasContacts = person.aiSummaryContactCount > 0;
    if (!hasUrls && !hasFiles && !hasContacts) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('参照した情報', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
          const SizedBox(height: 4),
          if (hasContacts)
            Text('・接点メモ ${person.aiSummaryContactCount}件', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          for (final url in person.aiSummarySourceUrls)
            InkWell(
              onTap: () => _openLink(context, url),
              child: Text(
                '・HPリンク: $url',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline),
              ),
            ),
          for (final file in person.aiSummarySourceFiles)
            Text('・資料ファイル: $file', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

// F-010: AIカルテ生成／更新。任意でHPリンク・資料ファイルを指定し、根拠に含めることができる
Future<void> _showGenerateCardSheet(BuildContext context, WidgetRef ref, String personId) async {
  final generated = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _GenerateCardSheet(personId: personId),
  );
  if (generated == true) {
    ref.invalidate(personDetailProvider(personId));
  }
}

class _GenerateCardSheet extends ConsumerStatefulWidget {
  const _GenerateCardSheet({required this.personId});

  final String personId;

  @override
  ConsumerState<_GenerateCardSheet> createState() => _GenerateCardSheetState();
}

class _GenerateCardSheetState extends ConsumerState<_GenerateCardSheet> {
  final _hpUrl = TextEditingController();
  File? _file;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _hpUrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf', 'txt', 'md'],
    );
    final path = result?.files.single.path;
    if (path != null) setState(() => _file = File(path));
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      await ref.read(personRepositoryProvider).generateCard(
            widget.personId,
            hpUrl: _hpUrl.text.trim().isEmpty ? null : _hpUrl.text.trim(),
            file: _file,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AIカルテの生成に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('AIカルテを生成', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            '名刺・音声メモ・接点履歴のメモに加え、任意でHPリンクや資料ファイルを渡すと、それらも要約の根拠に含めます。'
            '既にAI要約がある場合は、前回の内容を踏まえて更新します。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _hpUrl,
            decoration: const InputDecoration(
              labelText: 'HPリンク（任意）',
              border: OutlineInputBorder(),
              hintText: 'https://example.com',
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          if (_file != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.attach_file),
                title: Text(_file!.uri.pathSegments.last, overflow: TextOverflow.ellipsis),
                trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _file = null)),
              ),
            )
          else
            OutlinedButton.icon(
              icon: const Icon(Icons.attach_file),
              label: const Text('資料ファイルを添付（任意）'),
              onPressed: _pickFile,
            ),
          const Text(
            '対応形式: 画像・PDF・テキスト（Word/Excel等は非対応。PDFに変換してから添付してください）',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('AIで生成する'),
          ),
          if (_isSubmitting)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'AIが考えています…（ローカルAIのため1分ほどかかる場合があります）',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

// F-005/F-006 AIによる人脈グラフ作成: 提案を取得し、確認のうえ選択した関係のみ登録する
Future<void> _showRelationSuggestions(BuildContext context, WidgetRef ref, String personId) async {
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(personRepositoryProvider);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  List<RelationSuggestion> suggestions;
  try {
    suggestions = await repo.suggestRelations(personId);
  } catch (e) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    messenger.showSnackBar(SnackBar(content: Text('提案の取得に失敗しました: $e')));
    return;
  }

  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

  if (suggestions.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('現時点でAIが提案できる関係性はありませんでした。')));
    return;
  }

  if (!context.mounted) return;
  final selected = await showDialog<List<RelationSuggestion>>(
    context: context,
    builder: (_) => _RelationSuggestionDialog(suggestions: suggestions),
  );

  if (selected == null || selected.isEmpty) return;

  try {
    await repo.confirmRelations(personId: personId, selected: selected);
    messenger.showSnackBar(SnackBar(content: Text('${selected.length}件の関係を登録しました')));
    ref.invalidate(personNetworkGraphProvider(personId));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('登録に失敗しました: $e')));
  }
}

class _RelationSuggestionDialog extends StatefulWidget {
  const _RelationSuggestionDialog({required this.suggestions});

  final List<RelationSuggestion> suggestions;

  @override
  State<_RelationSuggestionDialog> createState() => _RelationSuggestionDialogState();
}

class _RelationSuggestionDialogState extends State<_RelationSuggestionDialog> {
  late final Set<int> _selectedIndexes = {for (var i = 0; i < widget.suggestions.length; i++) i};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AIによる関係性の提案'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.suggestions.length,
          itemBuilder: (context, index) {
            final s = widget.suggestions[index];
            return CheckboxListTile(
              value: _selectedIndexes.contains(index),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selectedIndexes.add(index);
                } else {
                  _selectedIndexes.remove(index);
                }
              }),
              title: Text('${s.relatedPersonName}（${RelationTypeStyle.label(s.relationType)}）'),
              subtitle: Text('${s.reason}\n強さ: ${'★' * s.strength}'),
              isThreeLine: true,
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop([for (final i in _selectedIndexes) widget.suggestions[i]]),
          child: const Text('選択した関係を登録'),
        ),
      ],
    );
  }
}
