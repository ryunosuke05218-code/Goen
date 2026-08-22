import '../persons/models/person_models.dart';

export '../persons/models/person_models.dart' show IndustryCount;

class OccupationCount {
  OccupationCount({required this.occupationName, required this.count});

  final String occupationName;
  final int count;

  factory OccupationCount.fromJson(Map<String, dynamic> json) => OccupationCount(
        occupationName: json['occupationName'] as String,
        count: json['count'] as int,
      );
}

/// F-029: 今日から1週間以内に予定されている接点記録。タップで対象人物のカルテ（接点履歴）へ遷移する。
class UpcomingContact {
  UpcomingContact({
    required this.personId,
    required this.personName,
    required this.contactType,
    required this.occurredAt,
    this.place,
  });

  final String personId;
  final String personName;
  final String contactType;
  final DateTime occurredAt;
  final String? place;

  factory UpcomingContact.fromJson(Map<String, dynamic> json) => UpcomingContact(
        personId: json['personId'] as String,
        personName: json['personName'] as String,
        contactType: json['contactType'] as String,
        occurredAt: DateTime.parse(json['occurredAt'] as String).toLocal(),
        place: json['place'] as String?,
      );
}

class DashboardData {
  DashboardData({
    required this.totalCount,
    required this.industryBreakdown,
    required this.occupationBreakdown,
    required this.upcomingContacts,
  });

  final int totalCount;
  final List<IndustryCount> industryBreakdown;
  final List<OccupationCount> occupationBreakdown;
  final List<UpcomingContact> upcomingContacts;

  factory DashboardData.fromJson(Map<String, dynamic> json) => DashboardData(
        totalCount: json['totalCount'] as int,
        industryBreakdown: (json['industryBreakdown'] as List)
            .map((e) => IndustryCount.fromJson(e as Map<String, dynamic>))
            .toList(),
        occupationBreakdown: (json['occupationBreakdown'] as List)
            .map((e) => OccupationCount.fromJson(e as Map<String, dynamic>))
            .toList(),
        upcomingContacts: (json['upcomingContacts'] as List)
            .map((e) => UpcomingContact.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
