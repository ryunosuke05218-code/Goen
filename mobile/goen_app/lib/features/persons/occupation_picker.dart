import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../masters/master_providers.dart';
import 'models/person_models.dart';

/// F-030: 職種のコンボボックス欄。既存の候補から選ぶことも、一覧にない名称を自由入力することもでき、
/// 未登録の名称は登録（作成・更新）時にサーバー側でマスタへ即時登録される（未入力なら未設定のまま）。
/// [onSelected]は候補一覧から既存の職種を選んだ場合のみ呼ばれる（自由入力しただけでは呼ばれない）。
class _OccupationAutocompleteField extends StatefulWidget {
  const _OccupationAutocompleteField({
    required this.controller,
    required this.options,
    required this.helperText,
    this.onSelected,
  });

  final TextEditingController controller;
  final List<String> options;
  final String helperText;
  final void Function(String)? onSelected;

  @override
  State<_OccupationAutocompleteField> createState() => _OccupationAutocompleteFieldState();
}

class _OccupationAutocompleteFieldState extends State<_OccupationAutocompleteField> {
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
      onSelected: widget.onSelected,
      fieldViewBuilder: (context, fieldController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: fieldController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: '職種',
            border: const OutlineInputBorder(),
            helperText: widget.helperText,
          ),
        );
      },
    );
  }
}

/// F-030拡張: 業種プルダウンと職種コンボボックスをセットで扱うウィジェット。人物登録・編集画面で共通利用する。
/// 業種は固定8種（設定画面からの追加・編集・削除は不可）からのプルダウン選択、職種は自由入力可能なコンボボックス。
/// 双方向に連動する:
///   ・業種を選択すると、職種の候補はその業種に紐づく職種のみに絞り込まれる。
///   ・業種が未設定の状態で一覧から職種を選ぶと、その職種に紐づく業種が1つならその業種を自動設定し、
///     複数あれば業種プルダウンの選択肢をその複数業種のみに絞り込む（自由入力した新規の職種名では発生しない）。
class IndustryOccupationFields extends ConsumerStatefulWidget {
  const IndustryOccupationFields({
    super.key,
    required this.industryController,
    required this.occupationController,
  });

  final TextEditingController industryController;
  final TextEditingController occupationController;

  @override
  ConsumerState<IndustryOccupationFields> createState() => _IndustryOccupationFieldsState();
}

class _IndustryOccupationFieldsState extends ConsumerState<IndustryOccupationFields> {
  // 職種選択により業種の選択肢が複数業種に絞り込まれている場合のみ非null（未設定なら全業種を選択肢にする）
  Set<String>? _narrowedIndustryNames;

  void _onIndustryChanged(String? industryName) {
    setState(() {
      widget.industryController.text = industryName ?? '';
      _narrowedIndustryNames = null; // 業種を直接選び直したら、職種由来の絞り込みは解除する
    });
  }

  void _onOccupationSelected(String occupationName, List<OccupationTypeItem> occupations) {
    if (widget.industryController.text.isNotEmpty) return; // 業種が既に設定済みなら何もしない

    final matches = occupations.where((o) => o.occupationName == occupationName);
    final industryNames = matches.isEmpty ? const <String>[] : matches.first.industryNames;
    setState(() {
      if (industryNames.length == 1) {
        widget.industryController.text = industryNames.first;
        _narrowedIndustryNames = null;
      } else if (industryNames.length > 1) {
        _narrowedIndustryNames = industryNames.toSet();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final industriesAsync = ref.watch(industriesProvider);
    final occupationsAsync = ref.watch(occupationTypesProvider);

    final allIndustryNames = industriesAsync.value?.where((i) => i.isActive).map((i) => i.industryName).toList() ?? const [];
    final industryOptions =
        _narrowedIndustryNames == null ? allIndustryNames : allIndustryNames.where(_narrowedIndustryNames!.contains).toList();

    final selectedIndustryName = widget.industryController.text.isEmpty ? null : widget.industryController.text;
    // 編集対象の人物が、無効化済み等で現在の一覧に無い業種名を持っていた場合でも
    // 選択肢から消えて未設定に戻ってしまわないよう、既存値も選択肢に含めておく。
    final industryItems = <String>{...industryOptions, ?selectedIndustryName};

    final occupations = occupationsAsync.value ?? const [];
    final occupationOptions = occupations
        .where((o) => o.isActive)
        .where((o) => selectedIndustryName == null || o.industryNames.contains(selectedIndustryName))
        .map((o) => o.occupationName)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String?>(
          // 業種の値はプルダウン自身の操作だけでなく職種選択からも変わりうるため、valueが変わるたびに
          // ウィジェットを作り直させてDropdownButtonFormFieldのinitialValue反映漏れ（初回のみ反映される仕様）
          // を避ける。
          key: ValueKey('industry-$selectedIndustryName'),
          initialValue: selectedIndustryName,
          decoration: InputDecoration(
            labelText: '業種',
            border: const OutlineInputBorder(),
            helperText: _narrowedIndustryNames != null ? '選択した職種が属する業種のみ表示しています' : null,
          ),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('未設定')),
            for (final name in industryItems) DropdownMenuItem<String?>(value: name, child: Text(name)),
          ],
          onChanged: _onIndustryChanged,
        ),
        const SizedBox(height: 12),
        _OccupationAutocompleteField(
          controller: widget.occupationController,
          options: occupationOptions,
          helperText: selectedIndustryName == null
              ? '人脈図（人脈マップ）の業種＞職種グルーピングに使用します。一覧にない職種は入力すると新規登録されます'
              : '「$selectedIndustryName」に属する職種のみ表示しています。一覧にない職種は入力すると新規登録されます',
          onSelected: (name) => _onOccupationSelected(name, occupations),
        ),
      ],
    );
  }
}
