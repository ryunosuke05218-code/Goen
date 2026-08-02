class PersonListItem {
  PersonListItem({
    required this.personId,
    required this.fullName,
    this.fullNameKana,
    this.companyName,
    this.jobTitle,
    required this.importance,
    this.summary,
    this.lastContactAt,
    required this.contactCount,
  });

  final String personId;
  final String fullName;
  final String? fullNameKana;
  final String? companyName;
  final String? jobTitle;
  final int importance;
  final String? summary;
  final DateTime? lastContactAt;
  final int contactCount;

  factory PersonListItem.fromJson(Map<String, dynamic> json) => PersonListItem(
        personId: json['personId'] as String,
        fullName: json['fullName'] as String,
        fullNameKana: json['fullNameKana'] as String?,
        companyName: json['companyName'] as String?,
        jobTitle: json['jobTitle'] as String?,
        importance: json['importance'] as int,
        summary: json['summary'] as String?,
        lastContactAt: json['lastContactAt'] == null ? null : DateTime.parse(json['lastContactAt'] as String),
        contactCount: json['contactCount'] as int,
      );
}

class PersonDetail {
  PersonDetail({
    required this.personId,
    required this.fullName,
    this.fullNameKana,
    this.department,
    this.jobTitle,
    this.companyName,
    required this.importance,
    required this.importanceIsManual,
    required this.visibility,
    this.tel,
    this.mobile,
    this.email,
    this.address,
    this.note,
    this.aiSummary,
    this.aiBusiness,
    this.aiIssues,
    this.aiHobby,
    this.introducerPersonId,
    this.introducerPersonName,
  });

  final String personId;
  final String fullName;
  final String? fullNameKana;
  final String? department;
  final String? jobTitle;
  final String? companyName;
  final int importance;
  final bool importanceIsManual;
  final String visibility;
  final String? tel;
  final String? mobile;
  final String? email;
  final String? address;
  final String? note;
  final String? aiSummary;
  final String? aiBusiness;
  final String? aiIssues;
  final String? aiHobby;
  final String? introducerPersonId;
  final String? introducerPersonName;

  factory PersonDetail.fromJson(Map<String, dynamic> json) => PersonDetail(
        personId: json['personId'] as String,
        fullName: json['fullName'] as String,
        fullNameKana: json['fullNameKana'] as String?,
        department: json['department'] as String?,
        jobTitle: json['jobTitle'] as String?,
        companyName: json['companyName'] as String?,
        importance: json['importance'] as int,
        importanceIsManual: json['importanceIsManual'] as bool,
        visibility: json['visibility'] as String,
        tel: json['tel'] as String?,
        mobile: json['mobile'] as String?,
        email: json['email'] as String?,
        address: json['address'] as String?,
        note: json['note'] as String?,
        aiSummary: json['aiSummary'] as String?,
        aiBusiness: json['aiBusiness'] as String?,
        aiIssues: json['aiIssues'] as String?,
        aiHobby: json['aiHobby'] as String?,
        introducerPersonId: json['introducerPersonId'] as String?,
        introducerPersonName: json['introducerPersonName'] as String?,
      );
}

class ContactItem {
  ContactItem({
    required this.contactId,
    required this.contactType,
    required this.occurredAt,
    this.place,
    this.note,
    required this.hasMedia,
  });

  final String contactId;
  final String contactType;
  final DateTime occurredAt;
  final String? place;
  final String? note;
  final bool hasMedia;

  factory ContactItem.fromJson(Map<String, dynamic> json) => ContactItem(
        contactId: json['contactId'] as String,
        contactType: json['contactType'] as String,
        occurredAt: DateTime.parse(json['occurredAt'] as String),
        place: json['place'] as String?,
        note: json['note'] as String?,
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
      );
}

/// F-005/F-006 人脈グラフ: AIによる関係性提案（未確定）
class RelationSuggestion {
  RelationSuggestion({
    required this.relatedPersonId,
    required this.relatedPersonName,
    required this.relationType,
    required this.reason,
    required this.strength,
  });

  final String relatedPersonId;
  final String relatedPersonName;
  final String relationType;
  final String reason;
  final int strength;

  factory RelationSuggestion.fromJson(Map<String, dynamic> json) => RelationSuggestion(
        relatedPersonId: json['relatedPersonId'] as String,
        relatedPersonName: json['relatedPersonName'] as String,
        relationType: json['relationType'] as String,
        reason: json['reason'] as String,
        strength: json['strength'] as int,
      );
}

class NetworkNode {
  NetworkNode({
    required this.personId,
    required this.fullName,
    this.companyName,
    required this.importance,
    required this.depth,
    this.isSelf = false,
  });

  final String personId;
  final String fullName;
  final String? companyName;
  final int importance;
  final int depth;
  final bool isSelf;

  factory NetworkNode.fromJson(Map<String, dynamic> json) => NetworkNode(
        personId: json['personId'] as String,
        fullName: json['fullName'] as String,
        companyName: json['companyName'] as String?,
        importance: json['importance'] as int,
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
