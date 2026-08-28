namespace Goen.Infrastructure.ExternalAi;

// チャット/LLMプロバイダ設定。Groq・Ollama・Gemini・OpenAIはいずれもOpenAI互換のchat completions
// エンドポイントを提供するため、BaseUrl・Model・ApiKeyを差し替えるだけでプロバイダを切り替えられる。
// 例:
//   開発(Ollama)  : BaseUrl=http://192.168.1.2:11434/v1, Model=gemma3:4b, ApiKey=(任意の文字列でよい)
//   開発(Groq)    : BaseUrl=https://api.groq.com/openai/v1, Model=llama-3.3-70b-versatile, ApiKey=実キー
//   本番(Gemini)  : BaseUrl=https://generativelanguage.googleapis.com/v1beta/openai, Model=gemini-3.5-flash-lite, ApiKey=実キー
//     （名刺OCR・音声文字起こし中心の用途向けにコスパ重視でFlash-Liteを選定。複雑な推論が必要な機能
//      （AI人脈相談の経路探索等）で精度不足を感じたらModelだけgemini-3.6-flash等に差し替えればよい）
// ApiKeyは appsettings に直接書かず、必ず dotnet user-secrets または環境変数で設定すること。
public class AiChatOptions
{
    public const string SectionName = "Ai:Chat";

    public string Provider { get; set; } = "mock"; // mock / groq / ollama / gemini / openai
    public string BaseUrl { get; set; } = "http://192.168.1.2:11434/v1";
    public string Model { get; set; } = "gemma3:4b";
    public string ApiKey { get; set; } = "";
}
