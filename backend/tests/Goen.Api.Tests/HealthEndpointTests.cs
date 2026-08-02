using System.Net;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace Goen.Api.Tests;

public class HealthEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _factory;

    public HealthEndpointTests(WebApplicationFactory<Program> factory)
    {
        // appsettings.json の空のJwt:SigningKeyのままだとProgram.csが起動時に例外を投げるため、
        // テスト用の環境変数でダミー値を注入する（実DB接続は行わないためConnectionStringは空のままでよい）。
        Environment.SetEnvironmentVariable("Jwt__SigningKey", "test-signing-key-not-for-production-use-only");
        _factory = factory;
    }

    [Fact]
    public async Task Health_ReturnsOk()
    {
        var client = _factory.CreateClient();

        var response = await client.GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }
}
