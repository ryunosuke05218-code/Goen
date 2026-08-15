using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;

namespace Goen.Infrastructure.ExternalAi;

// F-009 音声メモの文字起こし（I-002）: 専用の音声認識APIを別途選定せず、名刺OCR（LlmVisionOcrService）と
// 同様にマルチモーダル対応のチャットLLMへ音声をそのまま渡して文字起こしさせる。Ai:Chat:*の設定を流用するため
// 専用のAPIキー等は不要。OpenAI互換のaudio入力形式（messages[].content配列にinput_audioを含める）は
// Gemini（gemini-2.5-flash等）のOpenAI互換エンドポイントで利用できる。
public class LlmSpeechToTextService : ISpeechToTextService
{
    private readonly HttpClient _http;
    private readonly AiChatOptions _options;

    public LlmSpeechToTextService(HttpClient http, IOptions<AiChatOptions> options)
    {
        _options = options.Value;
        http.BaseAddress = new Uri(_options.BaseUrl.TrimEnd('/') + "/");
        http.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", string.IsNullOrWhiteSpace(_options.ApiKey) ? "unused" : _options.ApiKey);
        _http = http;
    }

    public async Task<TranscriptionResult> TranscribeAsync(
        Stream audioStream, string? mimeType = null, CancellationToken cancellationToken = default)
    {
        using var buffer = new MemoryStream();
        await audioStream.CopyToAsync(buffer, cancellationToken);
        var bytes = buffer.ToArray();

        const string prompt = """
            これは日本語の音声メモです。話されている内容をそのまま文字に書き起こしてください。

            重要なルール:
            - 聞き取れた内容をそのまま書き起こすこと。要約・言い換え・内容の創作をしないこと。
            - 無音や雑音のみで発話が聞き取れない場合は、空文字列を返すこと。
            - 書き起こしたテキストのみを出力すること（前置き・説明・「」等の引用符は不要）。
            """;

        var request = new AudioChatRequest(
            Model: _options.Model,
            Messages: new[]
            {
                new AudioChatMessage("user", new object[]
                {
                    new TextContentPart("text", prompt),
                    new AudioContentPart("input_audio", new InputAudio(Convert.ToBase64String(bytes), AudioFormatFor(mimeType))),
                }),
            },
            Temperature: 0.1);

        using var response = await _http.PostAsJsonAsync("chat/completions", request, cancellationToken);
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadFromJsonAsync<ChatResponse>(cancellationToken: cancellationToken)
            ?? throw new InvalidOperationException($"{_options.Provider} APIから空の応答が返却されました。");

        var text = body.Choices.FirstOrDefault()?.Message.Content?.Trim() ?? "";

        return new TranscriptionResult(
            Text: text,
            // マルチモーダルLLMは伝統的な音声認識APIのような信頼度スコアを返さないため、
            // 書き起こしが得られたかどうかによる簡易的な目安値とする。
            Confidence: text.Length == 0 ? 0m : 0.8m,
            Model: $"{_options.Provider}:{_options.Model}",
            Language: "ja");
    }

    // Geminiが対応する形式（wav/mp3/aiff/aac/ogg/flac）へマッピングする。未知の形式はwavとして扱う。
    private static string AudioFormatFor(string? mimeType) => mimeType?.ToLowerInvariant() switch
    {
        "audio/wav" or "audio/x-wav" or "audio/wave" => "wav",
        "audio/mpeg" or "audio/mp3" => "mp3",
        "audio/aiff" or "audio/x-aiff" => "aiff",
        "audio/aac" or "audio/mp4" or "audio/x-m4a" or "audio/m4a" => "aac",
        "audio/ogg" => "ogg",
        "audio/flac" or "audio/x-flac" => "flac",
        _ => "wav",
    };

    private record AudioChatRequest(string Model, AudioChatMessage[] Messages, double Temperature);

    private record AudioChatMessage(string Role, object[] Content);

    private record TextContentPart(string Type, string Text);

    private record AudioContentPart(string Type, [property: JsonPropertyName("input_audio")] InputAudio InputAudio);

    private record InputAudio(string Data, string Format);

    private record ChatResponse(ChatChoice[] Choices);

    private record ChatChoice(ChatMessage Message);

    private record ChatMessage(string Content);
}
