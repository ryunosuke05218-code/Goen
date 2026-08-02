namespace Goen.Infrastructure.ExternalAi;

// F-009 音声メモ録音・文字起こし機能（I-002）
public record TranscriptionResult(string Text, decimal Confidence, string Model, string Language);

public interface ISpeechToTextService
{
    Task<TranscriptionResult> TranscribeAsync(Stream audioStream, CancellationToken cancellationToken = default);
}
