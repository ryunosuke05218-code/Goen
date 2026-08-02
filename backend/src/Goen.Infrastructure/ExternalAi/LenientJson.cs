using System.Text.Json;

namespace Goen.Infrastructure.ExternalAi;

// 小型ローカルモデル（gemma3:4b等）はJSON mode指定があっても前後に説明文を付けることがあるため、
// 素直なパースが失敗した場合は最初の '{' から最後の '}' までを抜き出して再試行する共通ヘルパー。
public static class LenientJson
{
    public static JsonElement Parse(string content)
    {
        try
        {
            return JsonDocument.Parse(content).RootElement;
        }
        catch (JsonException)
        {
            var start = content.IndexOf('{');
            var end = content.LastIndexOf('}');
            if (start < 0 || end <= start)
            {
                throw;
            }
            return JsonDocument.Parse(content[start..(end + 1)]).RootElement;
        }
    }
}
