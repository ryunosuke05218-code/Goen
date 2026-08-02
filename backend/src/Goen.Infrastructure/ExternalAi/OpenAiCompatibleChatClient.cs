using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;

namespace Goen.Infrastructure.ExternalAi;

// OpenAI互換のChat Completions API（/v1/chat/completions）を話すLLMなら何でも使える汎用実装。
// Groq・Ollama（gemma3等）・Gemini・OpenAIはいずれもこの形式に対応しているため、
// appsettings/User Secretsの Ai:Chat:BaseUrl / Model / ApiKey を差し替えるだけでプロバイダを切り替えられる
// （Program.cs側のコード変更は不要）。
public class OpenAiCompatibleChatClient : ILlmService
{
    private readonly HttpClient _http;
    private readonly AiChatOptions _options;

    public OpenAiCompatibleChatClient(HttpClient http, IOptions<AiChatOptions> options)
    {
        _options = options.Value;
        http.BaseAddress = new Uri(_options.BaseUrl.TrimEnd('/') + "/");
        // Ollamaは認証を要求しないが「何らかの値」がないとヘッダ自体を嫌うクライアントもあるため、
        // 未設定時はダミー値を入れておく（Ollama側では無視される）。
        http.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", string.IsNullOrWhiteSpace(_options.ApiKey) ? "unused" : _options.ApiKey);
        _http = http;
    }

    public async Task<PersonCardDraft> GeneratePersonCardAsync(
        string fullName,
        IReadOnlyCollection<string> sourceTexts,
        CancellationToken cancellationToken = default)
    {
        const string systemPrompt = """
            あなたは営業担当者向け人脈管理アプリのAIアシスタントです。
            与えられた人物に関する断片的な情報（名刺情報・音声メモの文字起こし・商談メモ等）から、
            人物カルテの項目を抽出してください。

            必ず次のJSON形式のみで出力してください（説明文や前置きは不要）:
            {"summary": "3〜5文の要約", "business": "事業内容またはnull", "issues": "抱える課題またはnull", "introducerName": "紹介者の氏名またはnull", "hobby": "趣味・人柄またはnull"}

            重要なルール:
            - 情報から読み取れない項目は必ず null にすること。推測や創作で埋めてはいけない。
            - summary は必ず日本語で3〜5文にまとめる。
            """;

        var userPrompt = $"""
            対象人物: {fullName}

            入力情報:
            {(sourceTexts.Count == 0 ? "(情報なし)" : string.Join("\n---\n", sourceTexts))}
            """;

        var json = await CallChatJsonAsync(systemPrompt, userPrompt, cancellationToken);

        return new PersonCardDraft(
            Summary: GetString(json, "summary") ?? $"{fullName}氏に関する情報がまだ十分にありません。",
            Business: GetString(json, "business"),
            Issues: GetString(json, "issues"),
            IntroducerName: GetString(json, "introducerName"),
            Hobby: GetString(json, "hobby"));
    }

    public async Task<IReadOnlyList<RelationSuggestion>> SuggestRelationsAsync(
        PersonContext target,
        IReadOnlyList<PersonContext> candidates,
        CancellationToken cancellationToken = default)
    {
        if (candidates.Count == 0)
        {
            return Array.Empty<RelationSuggestion>();
        }

        const string systemPrompt = """
            あなたは営業担当者向け人脈管理アプリのAIアシスタントです。
            対象人物(target)と候補者一覧(candidates)の情報（会社名・役職・AI要約・課題・紹介者名）を比較し、
            具体的な根拠がある場合にのみ人脈関係を提案してください。

            必ず次のJSON形式のみで出力してください（説明文や前置きは不要）:
            {"suggestions": [{"relatedPersonId": "候補者のid", "relationType": "referrer|community", "reason": "提案理由（日本語1文）", "strength": 1〜5の整数}]}

            重要なルール:
            - relatedPersonId は candidates に含まれる id を1文字も変更せずそのまま使うこと。
            - relationType は「紹介できる関係」なら referrer、それ以外の人脈・知人つながりなら community とすること。
              同じ会社であること自体は紹介関係の根拠にはならないため、それだけでは提案しないこと。
            - target.introducerName が候補者の氏名と一致する場合は referrer とすること。
            - 根拠が薄い・推測に頼る場合は提案しないこと（無理に件数を埋めない）。
            - 該当がなければ {"suggestions": []} を返すこと。
            """;

        var candidatesJson = JsonSerializer.Serialize(candidates.Select(c => new
        {
            id = c.PersonId,
            fullName = c.FullName,
            companyName = c.CompanyName,
            jobTitle = c.JobTitle,
            summary = c.Summary,
            issues = c.Issues,
        }));

        var userPrompt = $$"""
            target:
            {"id": "{{target.PersonId}}", "fullName": "{{target.FullName}}", "companyName": {{JsonSerializer.Serialize(target.CompanyName)}}, "jobTitle": {{JsonSerializer.Serialize(target.JobTitle)}}, "summary": {{JsonSerializer.Serialize(target.Summary)}}, "issues": {{JsonSerializer.Serialize(target.Issues)}}, "introducerName": {{JsonSerializer.Serialize(target.IntroducerName)}}}

            candidates:
            {{candidatesJson}}
            """;

        var json = await CallChatJsonAsync(systemPrompt, userPrompt, cancellationToken);

        if (!json.TryGetProperty("suggestions", out var arr) || arr.ValueKind != JsonValueKind.Array)
        {
            return Array.Empty<RelationSuggestion>();
        }

        var validIds = candidates.Select(c => c.PersonId).ToHashSet();
        var result = new List<RelationSuggestion>();

        foreach (var item in arr.EnumerateArray())
        {
            if (!Guid.TryParse(GetString(item, "relatedPersonId"), out var relatedId) || !validIds.Contains(relatedId))
            {
                continue; // AIが不正/幻覚のIDを返した場合は破棄する
            }

            var relationType = GetString(item, "relationType") ?? "community";
            if (!AllowedRelationTypes.Contains(relationType))
            {
                relationType = "community";
            }

            var reason = GetString(item, "reason") ?? "AIによる推定";
            var strength = item.TryGetProperty("strength", out var s) && s.TryGetInt32(out var sv) ? Math.Clamp(sv, 1, 5) : 3;

            result.Add(new RelationSuggestion(relatedId, relationType, reason, strength));
        }

        return result;
    }

    public async Task<string> ComposeTextAsync(string systemPrompt, string userPrompt, CancellationToken cancellationToken = default)
    {
        var request = new ChatRequest(
            Model: _options.Model,
            Messages: new[]
            {
                new ChatMessage("system", systemPrompt),
                new ChatMessage("user", userPrompt),
            },
            ResponseFormat: null,
            Temperature: 0.3);

        using var response = await _http.PostAsJsonAsync("chat/completions", request, cancellationToken);
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadFromJsonAsync<ChatResponse>(cancellationToken: cancellationToken)
            ?? throw new InvalidOperationException($"{_options.Provider} APIから空の応答が返却されました。");

        return body.Choices.FirstOrDefault()?.Message.Content?.Trim()
            ?? throw new InvalidOperationException($"{_options.Provider} APIの応答にcontentが含まれていません。");
    }

    private static readonly HashSet<string> AllowedRelationTypes =
        new() { "referrer", "community" };

    private async Task<JsonElement> CallChatJsonAsync(string systemPrompt, string userPrompt, CancellationToken ct)
    {
        var request = new ChatRequest(
            Model: _options.Model,
            Messages: new[]
            {
                new ChatMessage("system", systemPrompt),
                new ChatMessage("user", userPrompt),
            },
            ResponseFormat: new ResponseFormat("json_object"),
            Temperature: 0.2);

        using var response = await _http.PostAsJsonAsync("chat/completions", request, ct);
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadFromJsonAsync<ChatResponse>(cancellationToken: ct)
            ?? throw new InvalidOperationException($"{_options.Provider} APIから空の応答が返却されました。");

        var content = body.Choices.FirstOrDefault()?.Message.Content
            ?? throw new InvalidOperationException($"{_options.Provider} APIの応答にcontentが含まれていません。");

        return LenientJson.Parse(content);
    }

    private static string? GetString(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) || value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
        {
            return null;
        }
        var s = value.GetString();
        return string.IsNullOrWhiteSpace(s) ? null : s;
    }

    private record ChatRequest(
        string Model,
        ChatMessage[] Messages,
        [property: JsonPropertyName("response_format")] ResponseFormat? ResponseFormat,
        double Temperature);

    private record ChatMessage(string Role, string Content);

    private record ResponseFormat(string Type);

    private record ChatResponse(ChatChoice[] Choices);

    private record ChatChoice(ChatMessage Message);
}
