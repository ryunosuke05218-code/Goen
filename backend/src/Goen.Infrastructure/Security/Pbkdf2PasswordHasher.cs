using System.Security.Cryptography;

namespace Goen.Infrastructure.Security;

// PBKDF2-HMACSHA256によるパスワードハッシュ化。.NET標準ライブラリのみで完結し、追加のNuGet依存を持たない。
// 要件定義書 6章は Argon2id を想定しているが、外部サービス選定（Q-004）未決のため、
// 本スキャフォールドでは依存の少ないPBKDF2を暫定採用する。差し替える場合は本クラスのみ置換すればよい。
public class Pbkdf2PasswordHasher
{
    private const int SaltSize = 16;
    private const int SubkeySize = 32;
    private const int Iterations = 100_000;

    public string Hash(string password)
    {
        var salt = RandomNumberGenerator.GetBytes(SaltSize);
        var subkey = Rfc2898DeriveBytes.Pbkdf2(password, salt, Iterations, HashAlgorithmName.SHA256, SubkeySize);
        var result = new byte[SaltSize + SubkeySize];
        Buffer.BlockCopy(salt, 0, result, 0, SaltSize);
        Buffer.BlockCopy(subkey, 0, result, SaltSize, SubkeySize);
        return Convert.ToBase64String(result);
    }

    public bool Verify(string password, string hash)
    {
        byte[] decoded;
        try
        {
            decoded = Convert.FromBase64String(hash);
        }
        catch (FormatException)
        {
            return false;
        }

        if (decoded.Length != SaltSize + SubkeySize)
        {
            return false;
        }

        var salt = decoded[..SaltSize];
        var expectedSubkey = decoded[SaltSize..];
        var actualSubkey = Rfc2898DeriveBytes.Pbkdf2(password, salt, Iterations, HashAlgorithmName.SHA256, SubkeySize);
        return CryptographicOperations.FixedTimeEquals(expectedSubkey, actualSubkey);
    }
}
