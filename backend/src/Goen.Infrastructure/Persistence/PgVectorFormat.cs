using System.Globalization;
using System.Text;

namespace Goen.Infrastructure.Persistence;

// pgvectorへの入出力は追加のNuGetパッケージ(Pgvector.EntityFrameworkCore等)を使わず、
// PostgreSQLのvector型が受け付けるテキスト表現 "[0.1,0.2,...]" を介して行う。
// NpgsqlCommandのパラメータはtextとして渡し、SQL側で "@p::vector" のようにキャストする。
public static class PgVectorFormat
{
    public static string ToLiteral(float[] vector)
    {
        var sb = new StringBuilder(vector.Length * 10);
        sb.Append('[');
        for (var i = 0; i < vector.Length; i++)
        {
            if (i > 0) sb.Append(',');
            sb.Append(vector[i].ToString("G9", CultureInfo.InvariantCulture));
        }
        sb.Append(']');
        return sb.ToString();
    }
}
