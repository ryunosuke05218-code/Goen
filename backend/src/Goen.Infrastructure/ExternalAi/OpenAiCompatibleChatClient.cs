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
        IReadOnlyCollection<AttachmentInput>? attachments = null,
        CancellationToken cancellationToken = default)
    {
        const string systemPrompt = """
            あなたは営業担当者向け人脈管理アプリのAIアシスタントです。
            与えられた人物に関する断片的な情報（名刺情報・音声メモの文字起こし・接点メモ・前回の要約・
            添付されたHPリンクの本文や資料ファイル等）から、人物カルテの項目を抽出してください。

            必ず次のJSON形式のみで出力してください（説明文や前置きは不要）:
            {"summary": "3〜5個の要点の要約", "business": "事業内容またはnull", "issues": "抱える課題またはnull", "introducerName": "紹介者の氏名またはnull", "hobby": "趣味・人柄またはnull"}

            重要なルール:
            - 情報から読み取れない項目は必ず null にすること。推測や創作で埋めてはいけない。
            - summary・business・issues・hobby は、要点が複数ある場合は箇条書き（各行を「・」で始め、改行\nで区切る）でまとめること。要点が1つしかない場合は箇条書きにせず簡潔な1文でよい。
            - 「前回の要約」が入力に含まれる場合は、それを踏まえたうえで新しい情報を反映した要約に更新すること。
            """;

        var userPrompt = $"""
            対象人物: {fullName}

            入力情報:
            {(sourceTexts.Count == 0 ? "(情報なし)" : string.Join("\n---\n", sourceTexts))}
            """;

        var json = attachments is { Count: > 0 }
            ? await CallChatJsonWithAttachmentsAsync(systemPrompt, userPrompt, attachments, cancellationToken)
            : await CallChatJsonAsync(systemPrompt, userPrompt, cancellationToken);

        return new PersonCardDraft(
            Summary: GetString(json, "summary") ?? $"{fullName}氏に関する情報がまだ十分にありません。",
            Business: GetString(json, "business"),
            Issues: GetString(json, "issues"),
            IntroducerName: GetString(json, "introducerName"),
            Hobby: GetString(json, "hobby"));
    }

    // F-010/F-026: 資料ファイル（画像・PDF）はテキスト抽出せず、名刺OCR（LlmVisionOcrService）と同様にBase64データURLとして
    // マルチモーダル入力に含める。複数添付する場合はすべて同一ユーザーメッセージ内の別コンテンツパートとして渡す。
    private static object[] BuildAttachmentContentParts(string userPrompt, IReadOnlyCollection<AttachmentInput> attachments)
    {
        var contentParts = new List<object> { new TextContentPart("text", userPrompt) };
        contentParts.AddRange(attachments.Select(a =>
            (object)new ImageContentPart("image_url", new ImageUrl($"data:{a.MimeType};base64,{Convert.ToBase64String(a.Bytes)}"))));
        return contentParts.ToArray();
    }

    private async Task<JsonElement> CallChatJsonWithAttachmentsAsync(
        string systemPrompt, string userPrompt, IReadOnlyCollection<AttachmentInput> attachments, CancellationToken ct)
    {
        var request = new VisionChatRequest(
            Model: _options.Model,
            Messages: new object[]
            {
                new ChatMessage("system", systemPrompt),
                new VisionChatMessage("user", BuildAttachmentContentParts(userPrompt, attachments)),
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

    // F-026: 紹介文作成でHPリンク・資料ファイルが添付された場合の自由文生成（JSON modeを使わない点がカルテ生成と異なる）
    private async Task<string> CallChatTextWithAttachmentsAsync(
        string systemPrompt, string userPrompt, IReadOnlyCollection<AttachmentInput> attachments, CancellationToken ct)
    {
        var request = new VisionChatRequest(
            Model: _options.Model,
            Messages: new object[]
            {
                new ChatMessage("system", systemPrompt),
                new VisionChatMessage("user", BuildAttachmentContentParts(userPrompt, attachments)),
            },
            ResponseFormat: null,
            Temperature: 0.3);

        using var response = await _http.PostAsJsonAsync("chat/completions", request, ct);
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadFromJsonAsync<ChatResponse>(cancellationToken: ct)
            ?? throw new InvalidOperationException($"{_options.Provider} APIから空の応答が返却されました。");

        return body.Choices.FirstOrDefault()?.Message.Content?.Trim()
            ?? throw new InvalidOperationException($"{_options.Provider} APIの応答にcontentが含まれていません。");
    }

    private record VisionChatRequest(
        string Model,
        object[] Messages,
        [property: JsonPropertyName("response_format")] ResponseFormat? ResponseFormat,
        double Temperature);

    private record VisionChatMessage(string Role, object[] Content);

    private record TextContentPart(string Type, string Text);

    private record ImageContentPart(string Type, [property: JsonPropertyName("image_url")] ImageUrl ImageUrl);

    private record ImageUrl(string Url);

    public async Task<string> ComposeTextAsync(
        string systemPrompt,
        string userPrompt,
        IReadOnlyCollection<AttachmentInput>? attachments = null,
        CancellationToken cancellationToken = default)
    {
        if (attachments is { Count: > 0 })
        {
            return await CallChatTextWithAttachmentsAsync(systemPrompt, userPrompt, attachments, cancellationToken);
        }

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
