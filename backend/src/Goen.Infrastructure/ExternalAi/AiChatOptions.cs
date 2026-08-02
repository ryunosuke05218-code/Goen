namespace Goen.Infrastructure.ExternalAi;

// チャット/LLMプロバイダ設定。Groq・Ollama・Gemini・OpenAIはいずれもOpenAI互換のchat completions
// エンドポイントを提供するため、BaseUrl・Model・ApiKeyを差し替えるだけでプロバイダを切り替えられる。
// 例:
//   開発(Ollama)  : BaseUrl=http://localhost:11434/v1, Model=gemma3:4b, ApiKey=(任意の文字列でよい)
//   開発(Groq)    : BaseUrl=https://api.groq.com/openai/v1, Model=llama-3.3-70b-versatile, ApiKey=実キー
//   本番(Gemini)  : BaseUrl=https://generativelanguage.googleapis.com/v1beta/openai, Model=gemini-2.5-flash, ApiKey=実キー
// ApiKeyは appsettings に直接書かず、必ず dotnet user-secrets または環境変数で設定すること。
public class AiChatOptions
{
    public const string SectionName = "Ai:Chat";

    public string Provider { get; set; } = "mock"; // mock / groq / ollama / gemini / openai
    public string BaseUrl { get; set; } = "http://localhost:11434/v1";
    public string Model { get; set; } = "gemma3:4b";
    public string ApiKey { get; set; } = "";
}
