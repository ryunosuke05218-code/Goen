namespace Goen.Infrastructure.ExternalAi;

// 外部音声認識API（I-002）未選定（要件Q-004）のため、開発用のダミー実装を提供する。
public class MockSpeechToTextService : ISpeechToTextService
{
    public Task<TranscriptionResult> TranscribeAsync(Stream audioStream, CancellationToken cancellationToken = default)
    {
        var result = new TranscriptionResult(
            Text: "（音声メモのダミー文字起こし）先方は動画制作会社を探しているとのこと。紹介者は鈴木さん。来週水曜に再度連絡する。",
            Confidence: 0.5m,
            Model: "mock-asr-v0",
            Language: "ja");

        return Task.FromResult(result);
    }
}
