import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../masters/master_providers.dart';

/// F-030: 業種／職種のコンボボックス欄。既存の候補から選ぶことも、一覧にない名称を自由入力することもでき、
/// 未登録の名称は登録（作成・更新）時にサーバー側でマスタへ即時登録される（未入力なら未設定のまま）。
class _MasterComboBoxField extends StatefulWidget {
  const _MasterComboBoxField({
    required this.controller,
    required this.label,
    required this.helperText,
    required this.options,
  });

  final TextEditingController controller;
  final String label;
  final String helperText;
  final List<String> options;

  @override
  State<_MasterComboBoxField> createState() => _MasterComboBoxFieldState();
}

class _MasterComboBoxFieldState extends State<_MasterComboBoxField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim();
        if (query.isEmpty) return widget.options;
        return widget.options.where((o) => o.contains(query));
      },
      fieldViewBuilder: (context, fieldController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: fieldController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
            helperText: widget.helperText,
          ),
        );
      },
    );
  }
}

/// 職種のコンボボックス。人物登録・編集画面で共通利用する。
class OccupationComboBox extends ConsumerWidget {
  const OccupationComboBox({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final occupationsAsync = ref.watch(occupationTypesProvider);
    final options = occupationsAsync.value?.where((o) => o.isActive).map((o) => o.occupationName).toList() ?? const [];

    return _MasterComboBoxField(
      controller: controller,
      label: '職種',
      helperText: '人脈図（人脈マップ）の業種＞職種グルーピングに使用します。一覧にない職種は入力すると新規登録されます',
      options: options,
    );
  }
}

/// 業種のコンボボックス。人物登録・編集画面で共通利用する。
class IndustryComboBox extends ConsumerWidget {
  const IndustryComboBox({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final industriesAsync = ref.watch(industriesProvider);
    final options = industriesAsync.value?.where((i) => i.isActive).map((i) => i.industryName).toList() ?? const [];

    return _MasterComboBoxField(
      controller: controller,
      label: '業種',
      helperText: '一覧にない業種は入力すると新規登録されます',
      options: options,
    );
  }
}
