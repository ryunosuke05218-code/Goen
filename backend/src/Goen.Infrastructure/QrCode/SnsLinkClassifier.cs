namespace Goen.Infrastructure.QrCode;

// URLのドメインから代表的なSNSサービス名を推定する。判定できない場合は汎用ラベルとする
// （利用者が入力フォーム側でラベルを修正できるため、誤判定があっても登録自体は妨げない）。
public static class SnsLinkClassifier
{
    public static string GuessLabel(string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri))
        {
            return "リンク";
        }

        var host = uri.Host.ToLowerInvariant();

        if (host.Contains("instagram.com")) return "Instagram";
        if (host.Contains("facebook.com") || host.Contains("fb.me")) return "Facebook";
        if (host.Contains("twitter.com") || host.Contains("x.com")) return "X (Twitter)";
        if (host.Contains("linkedin.com")) return "LinkedIn";
        if (host.Contains("line.me") || host.Contains("lin.ee")) return "LINE";
        if (host.Contains("youtube.com") || host.Contains("youtu.be")) return "YouTube";
        if (host.Contains("tiktok.com")) return "TikTok";
        if (host.Contains("threads.net")) return "Threads";
        if (host.Contains("note.com")) return "note";
        return "リンク";
    }
}
