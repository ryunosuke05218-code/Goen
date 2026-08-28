/// SNSリンク（人物カルテで何個でも追加可能）。名刺のQRコードから読み取った場合はlabelが自動推定される
class SnsLink {
  SnsLink({this.label, required this.url});

  final String? label;
  final String url;

  factory SnsLink.fromJson(Map<String, dynamic> json) => SnsLink(
        label: json['label'] as String?,
        url: json['url'] as String,
      );

  Map<String, dynamic> toJson() => {'label': label, 'url': url};
}

class PersonListItem {
  PersonListItem({
    required this.personId,
    required this.fullName,
    this.fullNameKana,
    this.companyName,
    this.jobTitle,
    this.summary,
    this.lastContactAt,
    required this.contactCount,
  });

  final String personId;
  final String fullName;
  final String? fullNameKana;
  final String? companyName;
  final String? jobTitle;
  final String? summary;
  final DateTime? lastContactAt;
  final int contactCount;

  factory PersonListItem.fromJson(Map<String, dynamic> json) => PersonListItem(
        personId: json['personId'] as String,
        fullName: json['fullName'] as String,
        fullNameKana: json['fullNameKana'] as String?,
        companyName: json['companyName'] as String?,
        jobTitle: json['jobTitle'] as String?,
        summary: json['summary'] as String?,
        lastContactAt: json['lastContactAt'] == null ? null : DateTime.parse(json['lastContactAt'] as String),
        contactCount: json['contactCount'] as int,
      );
}

/// F-003: 一覧の総登録人数を併せて保持する
class PersonListResponse {
  PersonListResponse({required this.items, required this.totalCount});

  final List<PersonListItem> items;
  final int totalCount;

  factory PersonListResponse.fromJson(Map<String, dynamic> json) => PersonListResponse(
        items: (json['items'] as List).map((e) => PersonListItem.fromJson(e as Map<String, dynamic>)).toList(),
        totalCount: json['totalCount'] as int,
      );
}

/// F-003: 人物一覧のソート順
enum PersonSortOrder {
  lastContact('', '最終接触が新しい順'),
  registeredDesc('registered_desc', '登録が新しい順'),
  registeredAsc('registered_asc', '登録が古い順'),
  nameAsc('name_asc', 'あいうえお順');

  const PersonSortOrder(this.queryValue, this.label);
  final String queryValue;
  final String label;
}

/// 業種マスタ（F-030の職種追加画面・業種/職種管理画面で使用）
class IndustryItem {
  IndustryItem({required this.industryCode, required this.industryName, required this.isActive});

  final String industryCode;
  final String industryName;
  final bool isActive;

  factory IndustryItem.fromJson(Map<String, dynamic> json) => IndustryItem(
        industryCode: json['industryCode'] as String,
        industryName: json['industryName'] as String,
        isActive: json['isActive'] as bool,
      );
}

/// 職種マスタ（Q-011解消）。人脈図の階層グルーピング・人物編集画面の選択肢に使用。
/// F-030拡張: 職種は複数の業種にまたがりうるため、業種は一覧（industryCodes/industryNames）で持つ
class OccupationTypeItem {
  OccupationTypeItem({
    required this.occupationCode,
    required this.occupationName,
    required this.industryCodes,
    required this.industryNames,
    required this.isActive,
  });

  final String occupationCode;
  final String occupationName;
  final List<String> industryCodes;
  final List<String> industryNames;
  final bool isActive;

  factory OccupationTypeItem.fromJson(Map<String, dynamic> json) => OccupationTypeItem(
        occupationCode: json['occupationCode'] as String,
        occupationName: json['occupationName'] as String,
        industryCodes: (json['industryCodes'] as List).map((e) => e as String).toList(),
        industryNames: (json['industryNames'] as List).map((e) => e as String).toList(),
        isActive: json['isActive'] as bool,
      );
}

class PersonDetail {
  PersonDetail({
    required this.personId,
    required this.fullName,
    this.fullNameKana,
    this.department,
    this.jobTitle,
    this.occupationCode,
    this.occupationName,
    this.industryName,
    this.companyName,
    required this.visibility,
    this.tel,
    this.mobile,
    this.email,
    this.address,
    this.note,
    this.metPlace,
    this.snsLinks = const [],
    this.aiSummary,
    this.aiBusiness,
    this.aiIssues,
    this.aiHobby,
    this.introducerPersonId,
    this.introducerPersonName,
    this.aiSummarySourceUrls = const [],
    this.aiSummarySourceFiles = const [],
    this.aiSummaryContactCount = 0,
    this.isSelf = false,
  });

  final String personId;
  final String fullName;
  final String? fullNameKana;
  final String? department;
  final String? jobTitle;
  final String? occupationCode;
  final String? occupationName;
  final String? industryName;
  final String? companyName;
  final String visibility;
  final String? tel;
  final String? mobile;
  final String? email;
  final String? address;
  final String? note;
  final String? metPlace;
  final List<SnsLink> snsLinks;
  final String? aiSummary;
  final String? aiBusiness;
  final String? aiIssues;
  final String? aiHobby;
  final String? introducerPersonId;
  final String? introducerPersonName;
  // F-032: AI要約の参照元表示
  final List<String> aiSummarySourceUrls;
  final List<String> aiSummarySourceFiles;
  final int aiSummaryContactCount;
  final bool isSelf;

  factory PersonDetail.fromJson(Map<String, dynamic> json) => PersonDetail(
        personId: json['personId'] as String,
        fullName: json['fullName'] as String,
        fullNameKana: json['fullNameKana'] as String?,
        department: json['department'] as String?,
        jobTitle: json['jobTitle'] as String?,
        occupationCode: json['occupationCode'] as String?,
        occupationName: json['occupationName'] as String?,
        industryName: json['industryName'] as String?,
        companyName: json['companyName'] as String?,
        visibility: json['visibility'] as String,
        tel: json['tel'] as String?,
        mobile: json['mobile'] as String?,
        email: json['email'] as String?,
        address: json['address'] as String?,
        note: json['note'] as String?,
        metPlace: json['metPlace'] as String?,
        snsLinks: (json['snsLinks'] as List? ?? [])
            .map((e) => SnsLink.fromJson(e as Map<String, dynamic>))
            .toList(),
        aiSummary: json['aiSummary'] as String?,
        aiBusiness: json['aiBusiness'] as String?,
        aiIssues: json['aiIssues'] as String?,
        aiHobby: json['aiHobby'] as String?,
        introducerPersonId: json['introducerPersonId'] as String?,
        introducerPersonName: json['introducerPersonName'] as String?,
        aiSummarySourceUrls: (json['aiSummarySourceUrls'] as List? ?? []).cast<String>(),
        aiSummarySourceFiles: (json['aiSummarySourceFiles'] as List? ?? []).cast<String>(),
        aiSummaryContactCount: json['aiSummaryContactCount'] as int? ?? 0,
        isSelf: json['isSelf'] as bool? ?? false,
      );
}

// F-038 AI自動リサーチ: 氏名・会社名からAIがWeb検索して生成した参考情報。出典（sources）を必ず伴う。
class PersonResearchSource {
  PersonResearchSource({required this.title, required this.url});

  final String title;
  final String url;

  factory PersonResearchSource.fromJson(Map<String, dynamic> json) => PersonResearchSource(
        title: json['title'] as String,
        url: json['url'] as String,
      );
}

class PersonResearch {
  PersonResearch({required this.summary, required this.sources, required this.generatedAt});

  final String summary;
  final List<PersonResearchSource> sources;
  final DateTime generatedAt;

  factory PersonResearch.fromJson(Map<String, dynamic> json) => PersonResearch(
        summary: json['summary'] as String,
        sources: (json['sources'] as List? ?? [])
            .map((e) => PersonResearchSource.fromJson(e as Map<String, dynamic>))
            .toList(),
        generatedAt: DateTime.parse(json['generatedAt'] as String).toLocal(),
      );
}

class ContactItem {
  ContactItem({
    required this.contactId,
    required this.contactType,
    required this.occurredAt,
    this.place,
    this.note,
    this.noteSummary,
    required this.hasMedia,
  });

  final String contactId;
  final String contactType;
  final DateTime occurredAt;
  final String? place;
  final String? note;
  // F-011拡張: 接点メモのAI要約。ボタン押下時のみ生成・上書きされる（メモ編集だけでは自動更新されない）
  final String? noteSummary;
  final bool hasMedia;

  factory ContactItem.fromJson(Map<String, dynamic> json) => ContactItem(
        contactId: json['contactId'] as String,
        contactType: json['contactType'] as String,
        occurredAt: DateTime.parse(json['occurredAt'] as String),
        place: json['place'] as String?,
        note: json['note'] as String?,
        noteSummary: json['noteSummary'] as String?,
        hasMedia: json['hasMedia'] as bool,
      );
}

class OcrDraft {
  OcrDraft({
    this.fullName,
    this.fullNameKana,
    this.companyName,
    this.department,
    this.jobTitle,
    this.tel,
    this.mobile,
    this.email,
    this.address,
    this.snsLinks = const [],
  });

  final String? fullName;
  final String? fullNameKana;
  final String? companyName;
  final String? department;
  final String? jobTitle;
  final String? tel;
  final String? mobile;
  final String? email;
  final String? address;
  // F-007: 名刺のQRコードから読み取ったSNSリンクの下書き（AI不使用の決定的処理で検出）
  final List<SnsLink> snsLinks;

  factory OcrDraft.fromJson(Map<String, dynamic> json) => OcrDraft(
        fullName: json['fullName'] as String?,
        fullNameKana: json['fullNameKana'] as String?,
        companyName: json['companyName'] as String?,
        department: json['department'] as String?,
        jobTitle: json['jobTitle'] as String?,
        tel: json['tel'] as String?,
        mobile: json['mobile'] as String?,
        email: json['email'] as String?,
        address: json['address'] as String?,
        snsLinks: (json['snsLinks'] as List? ?? [])
            .map((e) => SnsLink.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// F-002: 手入力登録画面で、音声（文字起こし）だけからAIが抽出した登録項目の下書き
class PersonVoiceDraft {
  PersonVoiceDraft({
    this.fullName,
    this.fullNameKana,
    this.companyName,
    this.jobTitle,
    this.email,
    this.mobile,
    this.note,
    this.metPlace,
  });

  final String? fullName;
  final String? fullNameKana;
  final String? companyName;
  final String? jobTitle;
  final String? email;
  final String? mobile;
  final String? note;
  final String? metPlace;

  factory PersonVoiceDraft.fromJson(Map<String, dynamic> json) => PersonVoiceDraft(
        fullName: json['fullName'] as String?,
        fullNameKana: json['fullNameKana'] as String?,
        companyName: json['companyName'] as String?,
        jobTitle: json['jobTitle'] as String?,
        email: json['email'] as String?,
        mobile: json['mobile'] as String?,
        note: json['note'] as String?,
        metPlace: json['metPlace'] as String?,
      );
}

class NetworkNode {
  NetworkNode({
    required this.personId,
    required this.fullName,
    this.companyName,
    this.industryName,
    this.occupationName,
    required this.depth,
    this.isSelf = false,
  });

  final String personId;
  final String fullName;
  final String? companyName;
  final String? industryName;
  final String? occupationName;
  final int depth;
  final bool isSelf;

  factory NetworkNode.fromJson(Map<String, dynamic> json) => NetworkNode(
        personId: json['personId'] as String,
        fullName: json['fullName'] as String,
        companyName: json['companyName'] as String?,
        industryName: json['industryName'] as String?,
        occupationName: json['occupationName'] as String?,
        depth: json['depth'] as int,
        isSelf: json['isSelf'] as bool? ?? false,
      );
}

class NetworkEdge {
  NetworkEdge({
    required this.relationId,
    required this.fromPersonId,
    required this.toPersonId,
    required this.relationType,
    required this.strength,
  });

  final String relationId;
  final String fromPersonId;
  final String toPersonId;
  final String relationType;
  final int strength;

  factory NetworkEdge.fromJson(Map<String, dynamic> json) => NetworkEdge(
        relationId: json['relationId'] as String,
        fromPersonId: json['fromPersonId'] as String,
        toPersonId: json['toPersonId'] as String,
        relationType: json['relationType'] as String,
        strength: json['strength'] as int,
      );
}

class NetworkGraph {
  NetworkGraph({required this.nodes, required this.edges});

  final List<NetworkNode> nodes;
  final List<NetworkEdge> edges;

  factory NetworkGraph.fromJson(Map<String, dynamic> json) => NetworkGraph(
        nodes: (json['nodes'] as List).map((e) => NetworkNode.fromJson(e as Map<String, dynamic>)).toList(),
        edges: (json['edges'] as List).map((e) => NetworkEdge.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

// F-027: 同一組織内の他ユーザーの選択肢
class OrgMember {
  OrgMember({required this.userId, required this.displayName});

  final String userId;
  final String displayName;

  factory OrgMember.fromJson(Map<String, dynamic> json) => OrgMember(
        userId: json['userId'] as String,
        displayName: json['displayName'] as String,
      );
}

// F-027: 他ユーザーの人脈図を業種階層までに限定して閲覧する
class IndustryCount {
  IndustryCount({required this.industryName, required this.count});

  final String industryName;
  final int count;

  factory IndustryCount.fromJson(Map<String, dynamic> json) => IndustryCount(
        industryName: json['industryName'] as String,
        count: json['count'] as int,
      );
}

class IndustryBreakdown {
  IndustryBreakdown({
    required this.targetUserId,
    required this.targetUserDisplayName,
    required this.totalCount,
    required this.industries,
  });

  final String targetUserId;
  final String targetUserDisplayName;
  final int totalCount;
  final List<IndustryCount> industries;

  factory IndustryBreakdown.fromJson(Map<String, dynamic> json) => IndustryBreakdown(
        targetUserId: json['targetUserId'] as String,
        targetUserDisplayName: json['targetUserDisplayName'] as String,
        totalCount: json['totalCount'] as int,
        industries:
            (json['industries'] as List).map((e) => IndustryCount.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

// ログイン中ユーザー自身の設定（表示名、F-028相互人脈登録、通知のON/OFF）
class UserSettings {
  UserSettings({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.allowMutualRegistration,
    required this.allowNotifications,
  });

  final String userId;
  final String email;
  final String displayName;
  final bool allowMutualRegistration;
  final bool allowNotifications;

  factory UserSettings.fromJson(Map<String, dynamic> json) => UserSettings(
        userId: json['userId'] as String,
        email: json['email'] as String,
        displayName: json['displayName'] as String,
        allowMutualRegistration: json['allowMutualRegistration'] as bool,
        allowNotifications: json['allowNotifications'] as bool,
      );
}
