namespace Goen.Infrastructure.ExternalAi;

// 外部OCR API（I-001）未選定（要件Q-004）のため、開発用のダミー実装を提供する。
// 実サービス選定後、本クラスと同じ IOcrService を実装するクラスに差し替える。
public class MockOcrService : IOcrService
{
    public Task<OcrResult> ExtractAsync(Stream imageStream, CancellationToken cancellationToken = default)
    {
        var result = new OcrResult(
            FullName: "山田 太郎",
            FullNameKana: "ヤマダ タロウ",
            CompanyName: "株式会社サンプル",
            Department: "営業部",
            JobTitle: "部長",
            Tel: "03-0000-0000",
            Mobile: "090-0000-0000",
            Email: "taro.yamada@example.com",
            Address: "東京都千代田区0-0-0",
            Url: "https://example.com",
            Confidence: 0.5m);

        return Task.FromResult(result);
    }
}
