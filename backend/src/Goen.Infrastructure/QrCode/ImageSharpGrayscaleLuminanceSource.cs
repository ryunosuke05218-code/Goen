using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using ZXing;

namespace Goen.Infrastructure.QrCode;

// NuGet公開版のZXing.Net.Bindings.ImageSharp（0.16.16時点）はSixLabors.ImageSharp 1.0.4向けにビルドされており、
// 脆弱性修正済みの現行バージョン（2.x以降）とは実行時に非互換（内部で呼び出すAPIがMissingMethodException）となる。
// そのためImageSharpのバインディングパッケージには依存せず、ZXing.Netコアの LuminanceSource を自前で実装する。
internal sealed class ImageSharpGrayscaleLuminanceSource : LuminanceSource
{
    private readonly byte[] _luminances;

    public ImageSharpGrayscaleLuminanceSource(Image<Rgba32> image) : base(image.Width, image.Height)
    {
        _luminances = new byte[image.Width * image.Height];

        image.ProcessPixelRows(accessor =>
        {
            for (var y = 0; y < accessor.Height; y++)
            {
                var row = accessor.GetRowSpan(y);
                var rowOffset = y * accessor.Width;
                for (var x = 0; x < row.Length; x++)
                {
                    var p = row[x];
                    // ITU-R BT.601相当の輝度変換（ZXing.Net標準のRGBLuminanceSourceと同じ係数）
                    _luminances[rowOffset + x] = (byte)((p.R * 306 + p.G * 601 + p.B * 117) >> 10);
                }
            }
        });
    }

    public override byte[] getRow(int y, byte[] row)
    {
        if (row is null || row.Length < Width)
        {
            row = new byte[Width];
        }
        Array.Copy(_luminances, y * Width, row, 0, Width);
        return row;
    }

    public override byte[] Matrix => _luminances;
}
