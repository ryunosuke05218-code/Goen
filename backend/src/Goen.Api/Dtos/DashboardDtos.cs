namespace Goen.Api.Dtos;

// F-029 ダッシュボード: 自分の人脈全体を俯瞰するための集計結果
public record DashboardResponse(
    int TotalCount,
    List<IndustryCountItem> IndustryBreakdown,
    List<OccupationCountItem> OccupationBreakdown,
    List<UpcomingContactItem> UpcomingContacts);

public record OccupationCountItem(string OccupationName, int Count);

// 次回アクション（次回接点予定）。タップすると対象人物のカルテ（接点履歴）へ遷移する
public record UpcomingContactItem(Guid PersonId, string PersonName, string Content, DateOnly? DueDate);
