import 'package:flutter/material.dart';

import 'models/person_models.dart';

/// SNSリンクを何個でも追加・削除できる入力欄。人物登録確認画面(S-004)・編集画面で共通利用する。
class SnsLinksEditor extends StatefulWidget {
  const SnsLinksEditor({super.key, required this.initialLinks, required this.onChanged});

  final List<SnsLink> initialLinks;
  final ValueChanged<List<SnsLink>> onChanged;

  @override
  State<SnsLinksEditor> createState() => _SnsLinksEditorState();
}

class _SnsLinksEditorState extends State<SnsLinksEditor> {
  late final List<_SnsLinkRow> _rows;

  @override
  void initState() {
    super.initState();
    _rows = widget.initialLinks.isEmpty
        ? [_SnsLinkRow()]
        : widget.initialLinks.map((l) => _SnsLinkRow(label: l.label, url: l.url)).toList();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _notify() {
    final links = _rows
        .where((r) => r.urlController.text.trim().isNotEmpty)
        .map((r) => SnsLink(
              label: r.labelController.text.trim().isEmpty ? null : r.labelController.text.trim(),
              url: r.urlController.text.trim(),
            ))
        .toList();
    widget.onChanged(links);
  }

  void _addRow() {
    setState(() => _rows.add(_SnsLinkRow()));
  }

  void _removeRow(int index) {
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
      if (_rows.isEmpty) _rows.add(_SnsLinkRow());
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SNSリンク', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        const Text(
          'Instagram・Facebookなど、何個でも追加できます',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _rows[i].labelController,
                    decoration: const InputDecoration(
                      labelText: 'ラベル',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _notify(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _rows[i].urlController,
                    decoration: const InputDecoration(
                      labelText: 'URL',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.url,
                    onChanged: (_) => _notify(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: '削除',
                  onPressed: () => _removeRow(i),
                ),
              ],
            ),
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('SNSリンクを追加'),
          onPressed: _addRow,
        ),
      ],
    );
  }
}

class _SnsLinkRow {
  _SnsLinkRow({String? label, String? url})
      : labelController = TextEditingController(text: label),
        urlController = TextEditingController(text: url);

  final TextEditingController labelController;
  final TextEditingController urlController;

  void dispose() {
    labelController.dispose();
    urlController.dispose();
  }
}
