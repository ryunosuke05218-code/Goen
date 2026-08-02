using System.Text;
using Goen.Infrastructure.ExternalAi;
using Goen.Infrastructure.Messaging;
using Goen.Infrastructure.Persistence;
using Goen.Infrastructure.Rag;
using Goen.Infrastructure.Security;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);

// ---- 設定 ----
builder.Services.Configure<JwtOptions>(builder.Configuration.GetSection(JwtOptions.SectionName));
builder.Services.Configure<AiChatOptions>(builder.Configuration.GetSection(AiChatOptions.SectionName));
builder.Services.Configure<AiEmbeddingOptions>(builder.Configuration.GetSection(AiEmbeddingOptions.SectionName));

// ---- DB (PostgreSQL / EF Core) ----
builder.Services.AddDbContext<GoenDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("GoenDb"))
           .UseSnakeCaseNamingConvention());

// ---- 認証・認可 (F-001) ----
var jwtSection = builder.Configuration.GetSection(JwtOptions.SectionName);
var signingKey = jwtSection["SigningKey"]
    ?? throw new InvalidOperationException("Jwt:SigningKey が設定されていません。appsettings または環境変数を確認してください。");

builder.Services
    .AddAuthentication(options =>
    {
        options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
        options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
    })
    .AddJwtBearer(options =>
    {
        // 既定では "sub" 等の短いクレーム名が ClaimTypes の長いURIへ自動マッピングされ、
        // JwtRegisteredClaimNames.Sub での参照（ClaimsPrincipalExtensions.GetUserId等）が失敗する。
        // 発行時のクレーム名をそのまま維持するため無効化する。
        options.MapInboundClaims = false;
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = jwtSection["Issuer"],
            ValidAudience = jwtSection["Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(signingKey)),
            ClockSkew = TimeSpan.FromSeconds(30),
        };
    });
builder.Services.AddAuthorization();

// ---- アプリケーションサービス ----
builder.Services.AddMemoryCache(); // F-001: ログイン失敗回数のロックアウト用
builder.Services.AddSingleton<Pbkdf2PasswordHasher>();
builder.Services.AddSingleton<JwtTokenService>();
builder.Services.AddScoped<PersonReadSyncService>();
builder.Services.AddScoped<NetworkGraphService>();

// 音声認識は外部サービス未選定（要件Q-004）のためダミー実装を登録する。
builder.Services.AddScoped<ISpeechToTextService, MockSpeechToTextService>();

// LLM・OCR・埋め込み: mock以外が指定されていればOpenAI互換クライアントを使う（Groq/Ollama/Gemini/OpenAI共通）。
// プロバイダの切替はappsettings/User Secretsの Ai:Chat:* / Ai:Embedding:* の値を変えるだけでよい。
var aiChatOptions = builder.Configuration.GetSection(AiChatOptions.SectionName).Get<AiChatOptions>() ?? new AiChatOptions();
if (!string.Equals(aiChatOptions.Provider, "mock", StringComparison.OrdinalIgnoreCase))
{
    builder.Services.AddHttpClient<ILlmService, OpenAiCompatibleChatClient>();
    // F-007 名刺OCR（I-001）: マルチモーダル対応のチャットLLM（gemma3等）に名刺画像を読み取らせる。
    // 専用のOCR APIを選定していない開発環境でも、Ai:Chat設定を流用してそのまま実用できる。
    builder.Services.AddHttpClient<IOcrService, LlmVisionOcrService>();
}
else
{
    builder.Services.AddScoped<ILlmService, MockLlmService>();
    builder.Services.AddScoped<IOcrService, MockOcrService>();
}

var aiEmbeddingOptions = builder.Configuration.GetSection(AiEmbeddingOptions.SectionName).Get<AiEmbeddingOptions>() ?? new AiEmbeddingOptions();
if (!string.Equals(aiEmbeddingOptions.Provider, "mock", StringComparison.OrdinalIgnoreCase))
{
    builder.Services.AddHttpClient<IEmbeddingService, OpenAiCompatibleEmbeddingService>();
}
else
{
    builder.Services.AddScoped<IEmbeddingService, MockEmbeddingService>();
}

// ---- RAG（F-004 曖昧検索 / AIアシスタントの経路提案・ヒント）----
builder.Services.AddScoped<RagIndexQueueService>();
builder.Services.AddScoped<RagChunkBuilder>();
builder.Services.AddScoped<RagChunkRepository>();
builder.Services.AddScoped<AiAssistantService>();
builder.Services.AddHostedService<RagIndexingWorker>();

// ---- F-026 紹介文（例文）作成（F-012 通知機能の廃止に伴う代替機能） ----
builder.Services.AddScoped<IntroLetterService>();

// ---- CORS（Flutter開発中のWeb/Emulatorアクセス用） ----
const string DevCorsPolicy = "DevCors";
builder.Services.AddCors(options =>
{
    options.AddPolicy(DevCorsPolicy, policy =>
        policy.SetIsOriginAllowed(_ => true).AllowAnyHeader().AllowAnyMethod());
});

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo { Title = "GOEN API", Version = "v1" });
    var jwtScheme = new OpenApiSecurityScheme
    {
        Scheme = "bearer",
        BearerFormat = "JWT",
        Name = "Authorization",
        In = ParameterLocation.Header,
        Type = SecuritySchemeType.Http,
        Description = "アクセストークンを 'Bearer {token}' の形式で指定してください。",
    };
    options.AddSecurityDefinition("Bearer", jwtScheme);
    options.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        { new OpenApiSecurityScheme { Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" } }, Array.Empty<string>() },
    });
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors(DevCorsPolicy);
if (!app.Environment.IsDevelopment())
{
    // 開発環境ではAndroidエミュレータ等がHTTPS(ASP.NET Core開発用の自己署名証明書)を信頼できず
    // HandshakeExceptionになるため、HTTPSリダイレクトは本番相当の環境（リバースプロキシでTLS終端）のみ有効にする。
    app.UseHttpsRedirection();
}
app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/health", () => Results.Ok(new { status = "ok", timestamp = DateTimeOffset.UtcNow }))
   .AllowAnonymous();

app.MapControllers();

app.Run();

public partial class Program; // 統合テスト（WebApplicationFactory）からの参照用
