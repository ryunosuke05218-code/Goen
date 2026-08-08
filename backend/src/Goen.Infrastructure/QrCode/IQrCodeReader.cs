namespace Goen.Infrastructure.QrCode;

// F-007 名刺画像に印刷されたQRコード（SNSリンク等）からURLを読み取る。
// マルチモーダルLLMによるQRコードの読み取りは不正確なため、専用のデコーダ（ZXing.Net）を用いた
// 決定的な処理とする（3.3 設計思想: ルールで確実に導けるものにAIを使わない、と同じ方針）。
public interface IQrCodeReader
{
    IReadOnlyList<string> ReadUrls(byte[] imageBytes);
}
