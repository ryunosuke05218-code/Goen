import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/person_models.dart';
import 'person_repository.dart';

String _contactTypeLabel(String type) => switch (type) {
      'card_exchange' => '名刺交換',
      'one_on_one' => '1to1',
      'meeting' => '商談',
      'referral' => '紹介',
      'event' => 'イベント同席',
      _ => 'その他',
    };

// Googleカレンダー側が要求するUTCの日時形式（YYYYMMDDTHHMMSSZ）に変換する
String _formatGoogleCalendarDate(DateTime dt) {
  final utc = dt.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}${two(utc.month)}${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
}

// APIキーやOAuthを使わず、Googleカレンダーの予定作成画面を事前入力した状態でブラウザ/アプリに開く。
// 最後の「保存」だけ利用者が行う必要があるが、連携のための認証設定が一切不要になる。
Uri _googleCalendarUrl({required String title, required DateTime start, String? location, String? details}) {
  final end = start.add(const Duration(hours: 1));
  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': title,
    'dates': '${_formatGoogleCalendarDate(start)}/${_formatGoogleCalendarDate(end)}',
    if (location != null && location.isNotEmpty) 'location': location,
    if (details != null && details.isNotEmpty) 'details': details,
  });
}

/// F-011 接点履歴タイムライン: 一覧の項目から遷移する接点詳細画面。何を話したか（メモ）を確認・編集する。
class ContactDetailScreen extends ConsumerStatefulWidget {
  const ContactDetailScreen({super.key, required this.personId, required this.personName, required this.contact});

  final String personId;
  final String personName;
  final ContactItem contact;

  @override
  ConsumerState<ContactDetailScreen> createState() => _ContactDetailScreenState();
}

class _ContactDetailScreenState extends ConsumerState<ContactDetailScreen> {
  late String? _note = widget.contact.note;
  bool _isEditing = false;
  bool _isSaving = false;
  late final TextEditingController _noteController = TextEditingController(text: _note);

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final trimmed = _noteController.text.trim();
      final updated = await ref.read(personRepositoryProvider).updateContactNote(
            personId: widget.personId,
            contactId: widget.contact.contactId,
            note: trimmed.isEmpty ? null : trimmed,
          );
      if (!mounted) return;
      setState(() {
        _note = updated.note;
        _isEditing = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _startEditing() {
    _noteController.text = _note ?? '';
    setState(() => _isEditing = true);
  }

  Future<void> _addToGoogleCalendar() async {
    final contact = widget.contact;
    final url = _googleCalendarUrl(
      title: '${widget.personName}さんとの${_contactTypeLabel(contact.contactType)}',
      start: contact.occurredAt,
      location: contact.place,
      details: _note,
    );
    final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Googleカレンダーを開けませんでした')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final contact = widget.contact;
    return Scaffold(
      appBar: AppBar(
        title: const Text('接点詳細'),
        actions: [
          IconButton(
            icon: const Icon(Icons.event_outlined),
            tooltip: 'Googleカレンダーに追加',
            onPressed: _addToGoogleCalendar,
          ),
          if (!_isEditing)
            IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'メモを編集', onPressed: _startEditing),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Icon(Icons.event_note_outlined),
              const SizedBox(width: 8),
              Text(_contactTypeLabel(contact.contactType), style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${contact.occurredAt.toLocal()}'.split('.').first,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          if (contact.place != null) ...[
            const SizedBox(height: 4),
            Text('場所: ${contact.place}'),
          ],
          const SizedBox(height: 24),
          Text('メモ', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          if (_isEditing) ...[
            TextField(
              controller: _noteController,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: '何を話したか、次のアクションなどを残しておきましょう',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : () => setState(() => _isEditing = false),
                    child: const Text('キャンセル'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('保存する'),
                  ),
                ),
              ],
            ),
          ] else
            Text(
              _note ?? 'この接点にはメモが記録されていません。',
              style: _note == null ? TextStyle(color: Theme.of(context).colorScheme.outline) : null,
            ),
        ],
      ),
    );
  }
}
