namespace Goen.Infrastructure.ExternalAi;

// F-009 音声メモ録音・文字起こし機能（I-002）
public record TranscriptionResult(string Text, decimal Confidence, string Model, string Language);

public interface ISpeechToTextService
{
    // mimeType: 音声フォーマットの判定に使う（例: "audio/wav"、"audio/mp4"）。未指定時は実装側で妥当な既定値にフォールバックする。
    Task<TranscriptionResult> TranscribeAsync(
        Stream audioStream, string? mimeType = null, CancellationToken cancellationToken = default);
}
