using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;

namespace Goen.Infrastructure.ExternalAi;

// F-007 名刺OCR（I-001）: マルチモーダル対応のチャットLLM（開発環境はOllama+gemma3、本番はgemini-2.5-flash想定）に
// 名刺画像を渡し、記載項目をJSONで抽出させる。Ai:Chat:* の設定を流用するため、専用のOCR APIキー等は不要。
// OpenAI互換のvision入力形式（messages[].content配列にimage_urlを含める）はOllama/Gemini双方で共通のため、
// AiChatOptionsのBaseUrl/Model/ApiKeyを差し替えるだけで本番プロバイダへ切り替えられる。
public class LlmVisionOcrService : IOcrService
{
    private readonly HttpClient _http;
    private readonly AiChatOptions _options;

    public LlmVisionOcrService(HttpClient http, IOptions<AiChatOptions> options)
    {
        _options = options.Value;
        http.BaseAddress = new Uri(_options.BaseUrl.TrimEnd('/') + "/");
        http.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", string.IsNullOrWhiteSpace(_options.ApiKey) ? "unused" : _options.ApiKey);
        _http = http;
    }

    public async Task<OcrResult> ExtractAsync(Stream imageStream, CancellationToken cancellationToken = default)
    {
        using var buffer = new MemoryStream();
        await imageStream.CopyToAsync(buffer, cancellationToken);
        var bytes = buffer.ToArray();
        var dataUrl = $"data:{SniffMimeType(bytes)};base64,{Convert.ToBase64String(bytes)}";

        const string prompt = """
            これは名刺の画像です。記載されている情報を読み取ってください。

            必ず次のJSON形式のみで出力してください（説明文や前置きは不要）:
            {"fullName": "氏名またはnull", "fullNameKana": "氏名のふりがな（カタカナ）またはnull", "companyName": "会社名またはnull", "department": "部署またはnull", "jobTitle": "役職またはnull", "tel": "電話番号またはnull", "mobile": "携帯番号またはnull", "email": "メールアドレスまたはnull", "address": "住所またはnull", "url": "WebサイトURLまたはnull"}

            重要なルール:
            - 名刺画像に記載されていない項目は必ず null にすること。推測や創作で埋めてはいけない。
            - 電話番号・携帯番号はハイフンを含め記載通りに転記すること。
            """;

        var request = new VisionChatRequest(
            Model: _options.Model,
            Messages: new[]
            {
                new VisionChatMessage("user", new object[]
                {
                    new TextContentPart("text", prompt),
                    new ImageContentPart("image_url", new ImageUrl(dataUrl)),
                }),
            },
            ResponseFormat: new ResponseFormat("json_object"),
            Temperature: 0.1);

        using var response = await _http.PostAsJsonAsync("chat/completions", request, cancellationToken);
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadFromJsonAsync<ChatResponse>(cancellationToken: cancellationToken)
            ?? throw new InvalidOperationException($"{_options.Provider} APIから空の応答が返却されました。");

        var content = body.Choices.FirstOrDefault()?.Message.Content
            ?? throw new InvalidOperationException($"{_options.Provider} APIの応答にcontentが含まれていません。");

        var json = LenientJson.Parse(content);
        var fullName = GetString(json, "fullName");

        return new OcrResult(
            FullName: fullName,
            FullNameKana: GetString(json, "fullNameKana"),
            CompanyName: GetString(json, "companyName"),
            Department: GetString(json, "department"),
            JobTitle: GetString(json, "jobTitle"),
            Tel: GetString(json, "tel"),
            Mobile: GetString(json, "mobile"),
            Email: GetString(json, "email"),
            Address: GetString(json, "address"),
            Url: GetString(json, "url"),
            // 伝統的なOCR APIのような文字単位の信頼度は得られないため、
            // 主要項目（氏名）を読み取れたかどうかによる簡易的な目安値とする。
            Confidence: fullName is null ? 0.3m : 0.7m);
    }

    // データURLに正しいMIMEタイプを付与するため、宣言されたファイル名/Content-Typeに頼らず
    // 実際のバイト列（マジックナンバー）から画像形式を判定する。
    private static string SniffMimeType(byte[] bytes)
    {
        if (bytes.Length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47)
        {
            return "image/png";
        }
        if (bytes.Length >= 12 && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50)
        {
            return "image/webp";
        }
        return "image/jpeg"; // カメラ撮影の既定はJPEGのため、判定不能時のフォールバックとする
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

    private record VisionChatRequest(
        string Model,
        VisionChatMessage[] Messages,
        [property: JsonPropertyName("response_format")] ResponseFormat? ResponseFormat,
        double Temperature);

    private record VisionChatMessage(string Role, object[] Content);

    private record TextContentPart(string Type, string Text);

    private record ImageContentPart(string Type, [property: JsonPropertyName("image_url")] ImageUrl ImageUrl);

    private record ImageUrl(string Url);

    private record ResponseFormat(string Type);

    private record ChatResponse(ChatChoice[] Choices);

    private record ChatChoice(ChatMessage Message);

    private record ChatMessage(string Content);
}
