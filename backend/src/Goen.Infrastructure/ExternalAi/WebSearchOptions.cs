namespace Goen.Infrastructure.ExternalAi;

// Web検索プロバイダ設定（I-006、F-038 AI自動リサーチ用）。
// ApiKeyは appsettings に直接書かず、必ず dotnet user-secrets または環境変数で設定すること。
public class WebSearchOptions
{
    public const string SectionName = "WebSearch";

    public string Provider { get; set; } = "mock"; // mock / tavily
    public string ApiKey { get; set; } = "";
}
