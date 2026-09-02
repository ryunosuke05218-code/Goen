using Goen.Infrastructure.ExternalAi;
using Microsoft.Extensions.Logging;

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
    private const int MaxSearchResultsPerQuery = 5;

    private readonly IWebSearchService _search;
    private readonly ILlmService _llm;
    private readonly ILogger<PersonResearchService> _logger;

    public PersonResearchService(IWebSearchService search, ILlmService llm, ILogger<PersonResearchService> logger)
    {
        _search = search;
        _llm = llm;
        _logger = logger;
    }

    public async Task<PersonResearchDraft> ResearchAsync(
        string fullName, string? companyName, string? jobTitle, CancellationToken ct)
    {
        // 人物名（多くは公人ではない一般の営業担当者等）は単独ではWeb上にほぼ情報が無いことが多く、
        // 人物名と会社名を1クエリに混ぜると、会社名の強い検索シグナルが人物名側のノイズに埋もれやすい。
        // そこで「会社情報そのもの」と「人物名＋会社名」の2クエリに分け、LLMにもどちらの検索由来かを
        // 明示して渡す（会社名は完全一致検索なので確度が高く、人物名側より積極的に使ってよいと伝える）。
        var companyResults = new List<WebSearchResult>();
        if (!string.IsNullOrWhiteSpace(companyName))
        {
            companyResults = (await _search.SearchAsync($"\"{companyName}\" 会社概要 事業内容", MaxSearchResultsPerQuery, ct)).ToList();
        }

        var personQueryParts = new[] { fullName, string.IsNullOrWhiteSpace(companyName) ? null : $"\"{companyName}\"" }
            .Where(s => !string.IsNullOrWhiteSpace(s));
        var personResults = (await _search.SearchAsync(string.Join(" ", personQueryParts), MaxSearchResultsPerQuery, ct))
            .Where(r => companyResults.All(c => c.Url != r.Url)) // 会社検索と重複するURLは会社側にのみ残す
            .ToList();

        var allResults = companyResults.Concat(personResults).ToList();

        _logger.LogInformation(
            "AIリサーチ検索結果 fullName=[{FullName}] companyName=[{CompanyName}] companyHits={CompanyCount} personHits={PersonCount}",
            fullName, companyName, companyResults.Count, personResults.Count);

        // 検索結果が無い場合、LLMに無理に生成させると実在しない情報を創作するリスクがあるため呼び出さない
        // （AiAssistantService.ComposeAnswerAsyncと同じ考え方）。
        if (allResults.Count == 0)
        {
            return new PersonResearchDraft("Web検索で参考になる情報が見つかりませんでした。", Array.Empty<PersonResearchSource>());
        }

        const string systemPrompt = """
            あなたは営業担当者向け人脈管理アプリのAIアシスタントです。
            以下は、ある人物・会社についてのWeb検索結果（タイトル・URL・抜粋）です。
            この検索結果に書かれている内容だけを根拠に、その人物・会社に関する短い参考情報を作成してください。

            検索結果は【企業情報】【人物関連情報】の2セクションに分かれています。
            - 【企業情報】は会社名の完全一致検索で得たものなので、社名さえ一致していれば別会社の情報が
              混じっている心配はほぼありません。会社概要・事業内容は積極的に紹介してください。
            - 【人物関連情報】は人物名を含む検索のため、同姓同名の可能性があります。本人だと断定できる
              確証がない場合は無理に人物の経歴を語らず、企業情報のみで回答して構いません。

            重要なルール:
            - 検索結果に書かれていない事実を絶対に創作・推測してはいけません。
            - 人物についての記載を含める場合、確信が持てなければ「同姓同名の可能性があり断定はできませんが」
              のように必ず明記してください。
            - 会社概要・事業内容だけでも有益な情報なので、人物本人の情報が無くても会社情報だけで
              回答して構いません（その場合、本人の情報が見つからなかった旨は書かなくてよい）。
            - 3〜5文程度で簡潔にまとめてください。
            - 企業情報・人物関連情報のどちらにも実質的に書ける内容が無い場合のみ、無理に文章を作らず
              「参考になる情報は見つかりませんでした」とだけ答えてください。
            """;

        var targetLine = $"氏名: {fullName}"
            + (string.IsNullOrWhiteSpace(companyName) ? "" : $" / 会社名: {companyName}")
            + (string.IsNullOrWhiteSpace(jobTitle) ? "" : $" / 役職: {jobTitle}");

        string FormatResults(List<WebSearchResult> list, int offset) => string.Join(
            "\n\n", list.Select((r, i) => $"[{offset + i + 1}] {r.Title}\nURL: {r.Url}\n{r.Snippet}"));

        var sections = new List<string>();
        if (companyResults.Count > 0) sections.Add("【企業情報】\n" + FormatResults(companyResults, 0));
        if (personResults.Count > 0) sections.Add("【人物関連情報】\n" + FormatResults(personResults, companyResults.Count));

        var userPrompt = $"【調査対象】{targetLine}\n\n{string.Join("\n\n", sections)}";

        var summary = await _llm.ComposeTextAsync(systemPrompt, userPrompt, cancellationToken: ct);

        // LLMが「参考になる情報は見つからなかった」と判断した場合、検索結果自体は無関係なものでも
        // 出典欄には残ってしまう（sourcesはresults全件から機械的に作るため）。要約が「見つからなかった」
        // 旨であれば、無関係な出典を見せて精度が低いという誤解を招かないよう出典も空にする。
        var foundNothing = summary.Contains("見つかりませんでした") || summary.Contains("見つかりません");
        var sources = foundNothing
            ? new List<PersonResearchSource>()
            : allResults.Select(r => new PersonResearchSource(r.Title, r.Url)).ToList();
        return new PersonResearchDraft(summary, sources);
    }
}
