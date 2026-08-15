using Goen.Infrastructure.ExternalAi;

namespace Goen.Infrastructure.Research;

public record PersonResearchSource(string Title, string Url);
public record PersonResearchDraft(string Summary, IReadOnlyList<PersonResearchSource> Sources);

// F-038 AI自動リサーチ: 氏名・会社名をもとにAIがWeb検索し、公開情報（会社概要・経歴・ニュース等）から
// 人物カルテの参考情報を自動生成する。
//
// 既存のAI要約（F-010）等は「実データ（ユーザー自身が登録した情報）のみを根拠にAIは文章化のみ行う」という
// 方針だが、本機能は公開Web情報という新しい種類の根拠を扱う。ユーザー自身のデータより信頼度の検証が
// 難しいため、通常のAI機能より一段厳しく「検索結果にない事実の創作を禁止」「同姓同名の可能性への言及」を
// プロンプトで強制し、事実ごとの出典（URL）を必ず保持する。
public class PersonResearchService
{
    private const int MaxSearchResults = 6;

    private readonly IWebSearchService _search;
    private readonly ILlmService _llm;

    public PersonResearchService(IWebSearchService search, ILlmService llm)
    {
        _search = search;
        _llm = llm;
    }

    public async Task<PersonResearchDraft> ResearchAsync(
        string fullName, string? companyName, string? jobTitle, CancellationToken ct)
    {
        var query = string.Join(" ", new[] { fullName, companyName }.Where(s => !string.IsNullOrWhiteSpace(s)));
        var results = await _search.SearchAsync(query, MaxSearchResults, ct);

        // 検索結果が無い場合、LLMに無理に生成させると実在しない情報を創作するリスクがあるため呼び出さない
        // （AiAssistantService.ComposeAnswerAsyncと同じ考え方）。
        if (results.Count == 0)
        {
            return new PersonResearchDraft("Web検索で参考になる情報が見つかりませんでした。", Array.Empty<PersonResearchSource>());
        }

        const string systemPrompt = """
            あなたは営業担当者向け人脈管理アプリのAIアシスタントです。
            以下は、ある人物・会社についてのWeb検索結果（タイトル・URL・抜粋）です。
            この検索結果に書かれている内容だけを根拠に、その人物・会社に関する短い参考情報を作成してください。

            重要なルール:
            - 検索結果に書かれていない事実を絶対に創作・推測してはいけません。
            - 複数の検索結果が本当に同一人物・同一会社の情報か確信が持てない場合は、
              「同姓同名の可能性があり断定はできませんが」のように必ず明記してください。
            - 会社概要・事業内容、本人の役職・経歴、最近のニュース（資金調達等）があれば触れてください。
            - 3〜5文程度で簡潔にまとめてください。
            - 参考にできる情報が実質的に無い場合は、無理に文章を作らず
              「参考になる情報は見つかりませんでした」とだけ答えてください。
            """;

        var targetLine = $"氏名: {fullName}"
            + (string.IsNullOrWhiteSpace(companyName) ? "" : $" / 会社名: {companyName}")
            + (string.IsNullOrWhiteSpace(jobTitle) ? "" : $" / 役職: {jobTitle}");

        var searchResultsText = string.Join(
            "\n\n",
            results.Select((r, i) => $"[{i + 1}] {r.Title}\nURL: {r.Url}\n{r.Snippet}"));

        var userPrompt = $"【調査対象】{targetLine}\n\n【検索結果】\n{searchResultsText}";

        var summary = await _llm.ComposeTextAsync(systemPrompt, userPrompt, cancellationToken: ct);

        var sources = results.Select(r => new PersonResearchSource(r.Title, r.Url)).ToList();
        return new PersonResearchDraft(summary, sources);
    }
}
