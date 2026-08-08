using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using ZXing;
using ZXing.Common;

namespace Goen.Infrastructure.QrCode;

public class ZXingQrCodeReader : IQrCodeReader
{
    public IReadOnlyList<string> ReadUrls(byte[] imageBytes)
    {
        Image<Rgba32> image;
        try
        {
            image = Image.Load<Rgba32>(imageBytes);
        }
        catch
        {
            // 未対応の画像形式・破損画像等はQRコードなしとして扱う（名刺の文字情報抽出は別経路のOCRが担当する）
            return Array.Empty<string>();
        }

        using (image)
        {
            var luminanceSource = new ImageSharpGrayscaleLuminanceSource(image);
            var reader = new BarcodeReaderGeneric
            {
                AutoRotate = true,
                Options = new DecodingOptions
                {
                    TryHarder = true,
                    PossibleFormats = new List<BarcodeFormat> { BarcodeFormat.QR_CODE },
                },
            };

            Result[]? results;
            try
            {
                results = reader.DecodeMultiple(luminanceSource);
            }
            catch
            {
                return Array.Empty<string>();
            }

            if (results is null) return Array.Empty<string>();

            return results
                .Select(r => r.Text)
                .Where(text => !string.IsNullOrWhiteSpace(text) && Uri.IsWellFormedUriString(text, UriKind.Absolute))
                .Distinct()
                .ToList();
        }
    }
}
