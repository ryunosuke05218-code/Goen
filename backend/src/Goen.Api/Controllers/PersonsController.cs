using System.Text.Json;
using Goen.Api.Dtos;
using Goen.Domain.Entities;
using Goen.Infrastructure.ExternalAi;
using Goen.Infrastructure.Persistence;
using Goen.Infrastructure.QrCode;
using Goen.Infrastructure.Rag;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Goen.Api.Controllers;

// F-002 人脈データ登録 / F-003 登録データ管理 / F-007 名刺OCR / F-011 接点履歴管理
[ApiController]
[Authorize]
[Route("api/persons")]
public class PersonsController : ControllerBase
{
    private readonly GoenDbContext _db;
    private readonly PersonReadSyncService _readSync;
    private readonly MasterDataService _masterData;
    private readonly NetworkGraphService _network;
    private readonly RagIndexQueueService _ragQueue;
    private readonly IOcrService _ocr;
    private readonly IQrCodeReader _qrReader;
    private readonly ISpeechToTextService _asr;
    private readonly ILlmService _llm;
    private readonly AiChatOptions _aiOptions;
    private readonly UrlTextFetcher _urlTextFetcher;

    public PersonsController(
        GoenDbContext db,
        PersonReadSyncService readSync,
        MasterDataService masterData,
        NetworkGraphService network,
        RagIndexQueueService ragQueue,
        IOcrService ocr,
        IQrCodeReader qrReader,
        ISpeechToTextService asr,
        ILlmService llm,
        IOptions<AiChatOptions> aiOptions,
        UrlTextFetcher urlTextFetcher)
    {
        _db = db;
        _readSync = readSync;
        _masterData = masterData;
        _network = network;
        _ragQueue = ragQueue;
        _ocr = ocr;
        _qrReader = qrReader;
        _asr = asr;
        _llm = llm;
        _aiOptions = aiOptions.Value;
        _urlTextFetcher = urlTextFetcher;
    }

    // F-004（簡易版）: persons_read への氏名・要約の部分一致検索。曖昧検索（RAG）は将来のフェーズで拡張する。
    // F-003: sortで並び順を切り替え、総登録人数（totalCount、絞り込み後の件数）を併せて返す。
    [HttpGet]
    public async Task<ActionResult<PersonListResponse>> List([FromQuery] string? q, [FromQuery] string? sort, CancellationToken ct)
    {
        var orgId = User.GetOrgId();
        var query = _db.PersonsRead.Where(r => r.OrgId == orgId);

        if (!string.IsNullOrWhiteSpace(q))
        {
            query = query.Where(r => EF.Functions.ILike(r.SearchText, $"%{q}%"));
        }

        var totalCount = await query.CountAsync(ct);

        query = sort switch
        {
            "name_asc" => query.OrderBy(r => r.FullNameKana ?? r.FullName),
            "registered_desc" => query.OrderByDescending(r => r.CreatedAt),
            "registered_asc" => query.OrderBy(r => r.CreatedAt),
            _ => query.OrderByDescending(r => r.LastContactAt),
        };

        var items = await query
            .Select(r => new PersonListItem(
                r.PersonId, r.FullName, r.FullNameKana, r.CompanyName, r.JobTitle,
                r.Summary, r.LastContactAt, r.ContactCount))
            .ToListAsync(ct);

        return Ok(new PersonListResponse(items, totalCount));
    }

    [HttpGet("{personId:guid}")]
    public async Task<ActionResult<PersonDetail>> Get(Guid personId, CancellationToken ct)
    {
        var person = await _db.Persons
            .Include(p => p.Company)
            .Include(p => p.Occupation)
            .Include(p => p.Profile)
            .Include(p => p.IntroducerPerson)
            .FirstOrDefaultAsync(p => p.PersonId == personId && p.OrgId == User.GetOrgId(), ct);

        if (person is null) return NotFound();

        var latestCard = await _db.AiPersonCards
            .Where(c => c.PersonId == personId && c.IsLatest)
            .FirstOrDefaultAsync(ct);

        var industryName = await GetIndustryNameAsync(person, ct);
        return Ok(ToDetail(person, latestCard, industryName));
    }

    [HttpPost]
    public async Task<ActionResult<PersonDetail>> Create(CreatePersonRequest request, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var orgId = User.GetOrgId();

        Guid? companyId = null;
        if (!string.IsNullOrWhiteSpace(request.CompanyName))
        {
            companyId = await ResolveCompanyAsync(request.CompanyName, ct);
        }

        // F-030: 職種・業種はコンボボックス（自由入力）で選択/入力される。未登録の名称はここでマスタに即時登録する
        var occupationCode = await _masterData.ResolveOccupationAsync(request.OccupationName, request.IndustryName, ct);

        // F-005 人脈グラフ（AIを使わない確実な自動生成）: 紹介者を選択式で指定してもらい、そのまま referrer 関係を張る
        Guid? introducerPersonId = null;
        if (request.IntroducerPersonId is { } candidateIntroducerId
            && await _db.Persons.AnyAsync(p => p.PersonId == candidateIntroducerId && p.OrgId == orgId, ct))
        {
            introducerPersonId = candidateIntroducerId;
        }

        var person = new Person
        {
            PersonId = Guid.NewGuid(),
            OrgId = orgId,
            OwnerUserId = userId,
            CompanyId = companyId,
            FullName = request.FullName,
            FullNameKana = request.FullNameKana,
            Department = request.Department,
            JobTitle = request.JobTitle,
            OccupationCode = occupationCode,
            SourceType = request.SourceType,
            IntroducerPersonId = introducerPersonId,
            FirstMetAt = DateOnly.FromDateTime(DateTime.UtcNow),
            MetPlace = request.MetPlace,
            CreatedAt = DateTimeOffset.UtcNow,
            CreatedBy = userId,
            UpdatedAt = DateTimeOffset.UtcNow,
            UpdatedBy = userId,
        };
        _db.Persons.Add(person);

        person.Profile = new PersonProfile
        {
            PersonId = person.PersonId,
            Tel = request.Tel,
            Mobile = request.Mobile,
            Email = request.Email,
            Address = request.Address,
            Note = request.Note,
            SnsAccountsJson = JsonSerializer.Serialize(request.SnsLinks ?? Array.Empty<SnsLink>()),
            CreatedAt = DateTimeOffset.UtcNow,
            CreatedBy = userId,
            UpdatedAt = DateTimeOffset.UtcNow,
            UpdatedBy = userId,
        };

        if (introducerPersonId is { } introducerId)
        {
            await UpsertRelationAsync(orgId, introducerId, person.PersonId, "referrer", strength: 3, isManual: true,
                note: "利用者が紹介者として選択登録", ct);
        }
        if (companyId is { } newCompanyId)
        {
            await AppendColleagueNoteAsync(orgId, person, newCompanyId, ct);
        }

        // F-028: 登録した人物がGOENの既存ユーザーだと本人確認できる場合、相手側にも自分を自動登録する
        Guid? mutuallyRegisteredPersonId = null;
        if (!string.IsNullOrWhiteSpace(request.Email))
        {
            mutuallyRegisteredPersonId = await TryCreateMutualRegistrationAsync(request.Email, userId, ct);
        }

        await _db.SaveChangesAsync(ct);
        await _readSync.RefreshAsync(person.PersonId, ct);
        await _ragQueue.EnqueueAsync("profile", person.PersonId, person.PersonId, 'U', ct);
        if (introducerPersonId is not null)
        {
            await _readSync.RefreshAsync(introducerPersonId.Value, ct);
        }
        if (mutuallyRegisteredPersonId is { } reciprocalId)
        {
            await _readSync.RefreshAsync(reciprocalId, ct);
            await _ragQueue.EnqueueAsync("profile", reciprocalId, reciprocalId, 'U', ct);
        }

        var created = await _db.Persons
            .Include(p => p.Company)
            .Include(p => p.Occupation)
            .Include(p => p.Profile)
            .Include(p => p.IntroducerPerson)
            .FirstAsync(p => p.PersonId == person.PersonId, ct);

        var createdIndustryName = await GetIndustryNameAsync(created, ct);
        return CreatedAtAction(nameof(Get), new { personId = person.PersonId }, ToDetail(created, null, createdIndustryName));
    }

    [HttpPut("{personId:guid}")]
    public async Task<ActionResult<PersonDetail>> Update(Guid personId, UpdatePersonRequest request, CancellationToken ct)
    {
        var person = await _db.Persons
            .Include(p => p.Profile)
            .Include(p => p.Company)
            .Include(p => p.Occupation)
            .Include(p => p.IntroducerPerson)
            .FirstOrDefaultAsync(p => p.PersonId == personId && p.OrgId == User.GetOrgId(), ct);
        if (person is null) return NotFound();

        // F-030: 職種・業種はコンボボックス（自由入力）で選択/入力される。未登録の名称はここでマスタに即時登録する
        var occupationCode = await _masterData.ResolveOccupationAsync(request.OccupationName, request.IndustryName, ct);

        person.FullName = request.FullName;
        person.FullNameKana = request.FullNameKana;
        person.Department = request.Department;
        person.JobTitle = request.JobTitle;
        person.OccupationCode = occupationCode;
        person.Occupation = occupationCode is null
            ? null
            : await _db.OccupationTypes.FindAsync(new object[] { occupationCode }, ct);
        person.Visibility = request.Visibility;
        person.MetPlace = request.MetPlace;
        person.UpdatedBy = User.GetUserId();

        if (!string.IsNullOrWhiteSpace(request.CompanyName))
        {
            var companyId = await ResolveCompanyAsync(request.CompanyName, ct);
            person.Company = await _db.Companies.FindAsync(new object[] { companyId }, ct);
        }
        else
        {
            person.Company = null;
        }

        person.Profile ??= new PersonProfile { PersonId = person.PersonId, CreatedAt = DateTimeOffset.UtcNow, CreatedBy = User.GetUserId() };
        person.Profile.Tel = request.Tel;
        person.Profile.Mobile = request.Mobile;
        person.Profile.Email = request.Email;
        person.Profile.Address = request.Address;
        person.Profile.Note = request.Note;
        person.Profile.SnsAccountsJson = JsonSerializer.Serialize(request.SnsLinks ?? Array.Empty<SnsLink>());
        person.Profile.UpdatedBy = User.GetUserId();

        await _db.SaveChangesAsync(ct);
        await _readSync.RefreshAsync(personId, ct);
        await _ragQueue.EnqueueAsync("profile", personId, personId, 'U', ct);

        var latestCard = await _db.AiPersonCards.FirstOrDefaultAsync(c => c.PersonId == personId && c.IsLatest, ct);
        var industryName = await GetIndustryNameAsync(person, ct);
        return Ok(ToDetail(person, latestCard, industryName));
    }

    [HttpDelete("{personId:guid}")]
    public async Task<IActionResult> Delete(Guid personId, CancellationToken ct)
    {
        var person = await _db.Persons.FirstOrDefaultAsync(p => p.PersonId == personId && p.OrgId == User.GetOrgId(), ct);
        if (person is null) return NotFound();

        _db.Persons.Remove(person); // 変更前イメージは h_persons へ自動退避される（DBトリガ）
        await _db.SaveChangesAsync(ct);
        await _readSync.RefreshAsync(personId, ct); // persons_read からも削除する
        await _ragQueue.EnqueuePersonDeletedAsync(personId, ct); // RAGチャンクも削除対象としてキューに積む

        return NoContent();
    }

    // F-007: 名刺画像→OCR抽出のドラフトを返す（この時点ではDB未登録。確認後にPOST /api/persons で確定登録する）
    // QRコード（SNSリンク等）はLLMではなく専用デコーダで読み取り、ドラフトのSNSリンク欄に変換して返す。
    [HttpPost("ocr-draft")]
    [RequestSizeLimit(10_000_000)]
    public async Task<ActionResult<OcrDraftResponse>> OcrDraft(IFormFile image, CancellationToken ct)
    {
        byte[] bytes;
        await using (var stream = image.OpenReadStream())
        {
            using var buffer = new MemoryStream();
            await stream.CopyToAsync(buffer, ct);
            bytes = buffer.ToArray();
        }

        using var ocrStream = new MemoryStream(bytes);
        var result = await _ocr.ExtractAsync(ocrStream, ct);

        var snsLinks = _qrReader.ReadUrls(bytes)
            .Select(url => new SnsLink(SnsLinkClassifier.GuessLabel(url), url))
            .ToList();

        return Ok(new OcrDraftResponse(
            result.FullName, result.FullNameKana, result.CompanyName, result.Department, result.JobTitle,
            result.Tel, result.Mobile, result.Email, result.Address, result.Url, result.Confidence, snsLinks));
    }

    // F-007: 登録内容確認画面で入力された音声文字起こしを、OCR結果（フォームの現在値）と統合する。
    // 画像は再送しない（ocr-draftとは独立したテキストのみのやり取り）。
    [HttpPost("ocr-draft/refine")]
    public async Task<ActionResult<OcrDraftResponse>> RefineOcrDraft(RefineOcrDraftRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.VoiceText))
        {
            return Ok(ToUnchangedOcrDraft(request));
        }

        const string systemPrompt = """
            あなたは名刺管理アプリのAIアシスタントです。
            名刺OCRで抽出済みの項目（不正確・欠落がある場合がある）と、利用者が口頭で補足した音声の文字起こしを
            統合し、より正確な人物の登録項目を求めてください。

            必ず次のJSON形式のみで出力してください（説明文や前置きは不要）:
            {"fullName": "氏名またはnull", "fullNameKana": "氏名のふりがな（カタカナ）またはnull", "companyName": "会社名またはnull", "department": "部署またはnull", "jobTitle": "役職またはnull", "tel": "電話番号またはnull", "mobile": "携帯番号またはnull", "email": "メールアドレスまたはnull", "address": "住所またはnull"}

            重要なルール:
            - 既存のOCR抽出結果と音声内容が矛盾する場合は、より具体的・確実な情報を優先すること。
            - どちらの情報源にも記載がない項目は必ずnullにすること。推測や創作で埋めてはいけない。
            """;

        var userPrompt = $$"""
            OCR抽出結果（既存の値。登録フォームに既に入っている内容）:
            {"fullName": {{JsonSerializer.Serialize(request.FullName)}}, "fullNameKana": {{JsonSerializer.Serialize(request.FullNameKana)}}, "companyName": {{JsonSerializer.Serialize(request.CompanyName)}}, "department": {{JsonSerializer.Serialize(request.Department)}}, "jobTitle": {{JsonSerializer.Serialize(request.JobTitle)}}, "tel": {{JsonSerializer.Serialize(request.Tel)}}, "mobile": {{JsonSerializer.Serialize(request.Mobile)}}, "email": {{JsonSerializer.Serialize(request.Email)}}, "address": {{JsonSerializer.Serialize(request.Address)}}}

            音声の文字起こし（利用者の口頭補足）:
            {{request.VoiceText}}
            """;

        try
        {
            var content = await _llm.ComposeTextAsync(systemPrompt, userPrompt, cancellationToken: ct);
            var json = LenientJson.Parse(content);

            return Ok(new OcrDraftResponse(
                GetString(json, "fullName") ?? request.FullName,
                GetString(json, "fullNameKana") ?? request.FullNameKana,
                GetString(json, "companyName") ?? request.CompanyName,
                GetString(json, "department") ?? request.Department,
                GetString(json, "jobTitle") ?? request.JobTitle,
                GetString(json, "tel") ?? request.Tel,
                GetString(json, "mobile") ?? request.Mobile,
                GetString(json, "email") ?? request.Email,
                GetString(json, "address") ?? request.Address,
                Url: null, Confidence: 1.0m, SnsLinks: Array.Empty<SnsLink>()));
        }
        catch
        {
            // AIでの統合に失敗した場合は元の値をそのまま返す（利用者が手動で編集を継続できる）
            return Ok(ToUnchangedOcrDraft(request));
        }
    }

    // F-002: 手入力登録画面向け。名刺OCR結果を前提としない、音声（文字起こし）だけからの項目抽出。
    // 話した内容をそのまま各登録項目・メモに振り分けることで、入力の手間を減らす。
    [HttpPost("voice-draft")]
    public async Task<ActionResult<VoiceDraftResponse>> CreateVoiceDraft(VoiceDraftRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.VoiceText))
        {
            return Ok(new VoiceDraftResponse(null, null, null, null, null, null, null, null));
        }

        const string systemPrompt = """
            あなたは人脈管理アプリのAIアシスタントです。
            利用者が名刺を使わず、出会った人物について口頭で話した内容の文字起こしから、
            人物登録フォームの各項目を抽出してください。

            必ず次のJSON形式のみで出力してください（説明文や前置きは不要）:
            {"fullName": "氏名またはnull", "fullNameKana": "氏名のふりがな（カタカナ）またはnull", "companyName": "会社名またはnull", "jobTitle": "役職またはnull", "email": "メールアドレスまたはnull", "mobile": "携帯番号またはnull", "metPlace": "出会った場所・機会（例：〇〇異業種交流会）またはnull", "note": "登録項目のどれにも当てはまらない残りの発言内容をまとめたメモ"}

            必ず次の順序で処理すること:
            1. まず氏名・ふりがな・会社名・役職・メールアドレス・携帯番号・出会った場所を、発言の中に明確な記載がある場合だけ、それぞれの項目にそのまま入れる（推測や創作で埋めない。記載がなければnull）。
            2. 次に、手順1でどの項目にも入れなかった残りの発言内容（年齢・趣味・家族構成・事業内容・課題・紹介者・次回アクションなど）だけをnoteにまとめる。手順1で各項目に入れた内容をnoteに重複して書かないこと。該当する残りの発言が本当に何もない場合のみnoteをnullにする。
            """;

        var userPrompt = $"音声の文字起こし:\n{request.VoiceText}";

        try
        {
            var content = await _llm.ComposeTextAsync(systemPrompt, userPrompt, cancellationToken: ct);
            var json = LenientJson.Parse(content);

            return Ok(new VoiceDraftResponse(
                GetString(json, "fullName"),
                GetString(json, "fullNameKana"),
                GetString(json, "companyName"),
                GetString(json, "jobTitle"),
                GetString(json, "email"),
                GetString(json, "mobile"),
                GetString(json, "note"),
                GetString(json, "metPlace")));
        }
        catch
        {
            // AIでの抽出に失敗した場合は、利用者が話した内容をそのままメモに残す（情報を失わないため）
            return Ok(new VoiceDraftResponse(null, null, null, null, null, null, request.VoiceText, null));
        }
    }

    // F-011: 接点履歴の登録
    [HttpPost("{personId:guid}/contacts")]
    public async Task<ActionResult<ContactItem>> AddContact(Guid personId, CreateContactRequest request, CancellationToken ct)
    {
        var person = await _db.Persons.FirstOrDefaultAsync(p => p.PersonId == personId && p.OrgId == User.GetOrgId(), ct);
        if (person is null) return NotFound();

        // PostgreSQLのtimestamptz列にはOffset=0（UTC）のDateTimeOffsetしか書き込めない（Npgsqlの制約）。
        // クライアントは端末のローカル時刻をそのまま送ってくる可能性があるため、保存前に必ずUTCへ正規化する。
        var occurredAtUtc = request.OccurredAt.ToUniversalTime();

        var contact = new Contact
        {
            ContactId = Guid.NewGuid(),
            OrgId = person.OrgId,
            PersonId = personId,
            UserId = User.GetUserId(),
            ContactType = request.ContactType,
            OccurredAt = occurredAtUtc,
            Place = request.Place,
            Note = request.Note,
            CreatedAt = DateTimeOffset.UtcNow,
            CreatedBy = User.GetUserId(),
            UpdatedAt = DateTimeOffset.UtcNow,
            UpdatedBy = User.GetUserId(),
        };
        _db.Contacts.Add(contact);

        if (person.LastContactAt is null || occurredAtUtc > person.LastContactAt)
        {
            person.LastContactAt = occurredAtUtc;
        }

        await _db.SaveChangesAsync(ct);
        await _readSync.RefreshAsync(personId, ct);
        if (!string.IsNullOrWhiteSpace(contact.Note))
        {
            await _ragQueue.EnqueueAsync("note", contact.ContactId, personId, 'U', ct);
        }

        return Ok(new ContactItem(contact.ContactId, contact.ContactType, contact.OccurredAt, contact.Place, contact.Note, contact.HasMedia));
    }

    // F-011: 接点履歴のメモを編集する（何を話したかを後から書き足す・修正する）
    [HttpPut("{personId:guid}/contacts/{contactId:guid}")]
    public async Task<ActionResult<ContactItem>> UpdateContactNote(Guid personId, Guid contactId, UpdateContactNoteRequest request, CancellationToken ct)
    {
        var contact = await _db.Contacts.FirstOrDefaultAsync(
            c => c.ContactId == contactId && c.PersonId == personId && c.OrgId == User.GetOrgId(), ct);
        if (contact is null) return NotFound();

        var hadNote = !string.IsNullOrWhiteSpace(contact.Note);
        contact.Note = string.IsNullOrWhiteSpace(request.Note) ? null : request.Note;
        contact.UpdatedBy = User.GetUserId();

        await _db.SaveChangesAsync(ct);

        if (contact.Note is not null)
        {
            await _ragQueue.EnqueueAsync("note", contact.ContactId, personId, 'U', ct);
        }
        else if (hadNote)
        {
            await _ragQueue.EnqueueAsync("note", contact.ContactId, personId, 'D', ct);
        }

        return Ok(new ContactItem(contact.ContactId, contact.ContactType, contact.OccurredAt, contact.Place, contact.Note, contact.HasMedia));
    }

    [HttpGet("{personId:guid}/contacts")]
    public async Task<ActionResult<IReadOnlyList<ContactItem>>> ListContacts(Guid personId, CancellationToken ct)
    {
        var exists = await _db.Persons.AnyAsync(p => p.PersonId == personId && p.OrgId == User.GetOrgId(), ct);
        if (!exists) return NotFound();

        var items = await _db.Contacts
            .Where(c => c.PersonId == personId)
            .OrderByDescending(c => c.OccurredAt)
            .Select(c => new ContactItem(c.ContactId, c.ContactType, c.OccurredAt, c.Place, c.Note, c.HasMedia))
            .ToListAsync(ct);

        return Ok(items);
    }

    // F-009: 音声メモを文字起こしし、接点ログに紐づけて保存する
    [HttpPost("{personId:guid}/contacts/{contactId:guid}/voice-memo")]
    [RequestSizeLimit(20_000_000)]
    public async Task<ActionResult<VoiceMemoResponse>> UploadVoiceMemo(Guid personId, Guid contactId, IFormFile audio, CancellationToken ct)
    {
        var contact = await _db.Contacts.FirstOrDefaultAsync(c => c.ContactId == contactId && c.PersonId == personId, ct);
        if (contact is null) return NotFound();

        await using var stream = audio.OpenReadStream();
        var asrResult = await _asr.TranscribeAsync(stream, ct);

        var media = new ContactMedia
        {
            MediaId = Guid.NewGuid(),
            ContactId = contactId,
            MediaType = "audio",
            StoragePath = $"local-dev/{contactId}/{audio.FileName}", // 開発用のダミーパス。本番はオブジェクトストレージへ保存する
            FileSize = audio.Length,
            UploadStatus = "uploaded",
            CreatedAt = DateTimeOffset.UtcNow,
            CreatedBy = User.GetUserId(),
            UpdatedAt = DateTimeOffset.UtcNow,
            UpdatedBy = User.GetUserId(),
        };
        _db.ContactMedia.Add(media);

        var transcript = new Transcript
        {
            TranscriptId = Guid.NewGuid(),
            ContactId = contactId,
            MediaId = media.MediaId,
            Content = asrResult.Text,
            Confidence = asrResult.Confidence,
            AsrModel = asrResult.Model,
            Language = asrResult.Language,
            Status = "done",
            CreatedAt = DateTimeOffset.UtcNow,
            CreatedBy = User.GetUserId(),
            UpdatedAt = DateTimeOffset.UtcNow,
            UpdatedBy = User.GetUserId(),
        };
        _db.Transcripts.Add(transcript);

        contact.HasMedia = true;
        contact.UpdatedBy = User.GetUserId();

        await _db.SaveChangesAsync(ct);
        await _ragQueue.EnqueueAsync("transcript", transcript.TranscriptId, personId, 'U', ct);

        return Ok(new VoiceMemoResponse(transcript.Content, asrResult.Confidence));
    }

    // F-010: 蓄積された接点・文字起こし・前回世代の要約に加え、任意のHPリンク・資料ファイルからAI人物カルテを生成する。
    // 資料ファイルは独自のテキスト抽出を行わず、名刺OCRと同様にマルチモーダルLLMへそのまま渡す（画像・PDFの場合）。
    // プレーンテキストファイルはそのままテキストとして入力に含める。
    [HttpPost("{personId:guid}/cards/generate")]
    [RequestSizeLimit(10_000_000)]
    public async Task<ActionResult<GenerateCardResponse>> GenerateCard(
        Guid personId, [FromForm] string? hpUrl, IFormFile? file, CancellationToken ct)
    {
        var person = await _db.Persons.FirstOrDefaultAsync(p => p.PersonId == personId && p.OrgId == User.GetOrgId(), ct);
        if (person is null) return NotFound();

        var sourceTexts = new List<string>();
        var inputSources = new List<object>();

        // 前回世代の要約（存在する場合）: これを踏まえて差分更新する
        var previousCard = await _db.AiPersonCards
            .Where(c => c.PersonId == personId && c.IsLatest)
            .FirstOrDefaultAsync(ct);
        if (!string.IsNullOrWhiteSpace(previousCard?.Summary))
        {
            sourceTexts.Add($"[前回のAI要約]\n{previousCard.Summary}");
        }

        // 音声メモ等の文字起こし
        var transcripts = await _db.Transcripts
            .Where(t => t.Contact.PersonId == personId)
            .OrderByDescending(t => t.CreatedAt)
            .Select(t => t.Content)
            .Take(20)
            .ToListAsync(ct);
        sourceTexts.AddRange(transcripts.Select(t => $"[音声文字起こし]\n{t}"));

        // 接点履歴の全メモ（商談・1to1・名刺交換時のメモ等）
        var contactNotes = await _db.Contacts
            .Where(c => c.PersonId == personId && c.Note != null && c.Note != "")
            .OrderByDescending(c => c.OccurredAt)
            .Select(c => c.Note!)
            .Take(30)
            .ToListAsync(ct);
        sourceTexts.AddRange(contactNotes.Select(n => $"[接点メモ]\n{n}"));

        // 任意: HPリンクの本文取得（失敗しても他の情報のみで続行する）
        if (!string.IsNullOrWhiteSpace(hpUrl))
        {
            var pageText = await _urlTextFetcher.TryFetchTextAsync(hpUrl, ct);
            if (pageText is not null)
            {
                sourceTexts.Add($"[HPリンクの内容: {hpUrl}]\n{pageText}");
                inputSources.Add(new { type = "url", value = hpUrl });
            }
        }

        // 任意: 資料ファイル。プレーンテキストはテキストとして入力に含め、画像・PDFはLLMへそのまま渡す
        var attachments = new List<AttachmentInput>();
        if (file is { Length: > 0 })
        {
            var contentType = file.ContentType.ToLowerInvariant();
            await using var fileStream = file.OpenReadStream();
            using var buffer = new MemoryStream();
            await fileStream.CopyToAsync(buffer, ct);
            var bytes = buffer.ToArray();

            if (contentType.StartsWith("text/"))
            {
                sourceTexts.Add($"[資料ファイル: {file.FileName}]\n{System.Text.Encoding.UTF8.GetString(bytes)}");
            }
            else if (contentType.StartsWith("image/") || contentType == "application/pdf")
            {
                attachments.Add(new AttachmentInput(bytes, contentType));
            }
            inputSources.Add(new { type = "file", value = file.FileName });
        }

        var contactIds = await _db.Contacts
            .Where(c => c.PersonId == personId)
            .Select(c => c.ContactId)
            .ToArrayAsync(ct);

        var draft = await _llm.GeneratePersonCardAsync(person.FullName, sourceTexts, attachments, ct);

        var previousGeneration = previousCard?.Generation ?? 0;

        await _db.AiPersonCards
            .Where(c => c.PersonId == personId && c.IsLatest)
            .ExecuteUpdateAsync(s => s.SetProperty(c => c.IsLatest, false), ct);

        var card = new AiPersonCard
        {
            CardId = Guid.NewGuid(),
            PersonId = personId,
            Generation = previousGeneration + 1,
            IsLatest = true,
            Summary = draft.Summary,
            Business = draft.Business,
            Issues = draft.Issues,
            IntroducerName = draft.IntroducerName,
            Hobby = draft.Hobby,
            LlmModel = $"{_aiOptions.Provider}:{_aiOptions.Model}",
            GeneratedAt = DateTimeOffset.UtcNow,
            InputContactIds = contactIds,
            InputSourcesJson = JsonSerializer.Serialize(inputSources),
            CreatedAt = DateTimeOffset.UtcNow,
            CreatedBy = User.GetUserId(),
            UpdatedAt = DateTimeOffset.UtcNow,
            UpdatedBy = User.GetUserId(),
        };
        _db.AiPersonCards.Add(card);

        // F-005 AIによる人脈グラフ作成: カルテの紹介者欄から、既存人物への関係(referrer)を自動的に張る
        await TryLinkIntroducerAsync(person, draft.IntroducerName, ct);

        await _db.SaveChangesAsync(ct);
        await _readSync.RefreshAsync(personId, ct);
        await _ragQueue.EnqueueAsync("card", card.CardId, personId, 'U', ct);

        return Ok(new GenerateCardResponse(card.Summary!, card.Business, card.Issues, card.Hobby, card.Generation));
    }

    // F-005/F-006 人脈グラフ: 対象人物と関連しそうな候補者をAIに提示し、関係の提案を受ける（未確定・DB未反映）
    [HttpGet("{personId:guid}/relations/suggest")]
    public async Task<ActionResult<IReadOnlyList<RelationSuggestionResponse>>> SuggestRelations(Guid personId, CancellationToken ct)
    {
        var orgId = User.GetOrgId();
        var target = await BuildPersonContextAsync(personId, orgId, ct);
        if (target is null) return NotFound();

        var candidates = await _db.Persons
            .Include(p => p.Company)
            .Where(p => p.OrgId == orgId && p.PersonId != personId)
            .OrderByDescending(p => p.LastContactAt)
            .Take(30) // 外部API呼び出しのトークン量・コストを抑えるため候補数を制限する
            .ToListAsync(ct);

        var candidateContexts = new List<PersonContext>();
        foreach (var c in candidates)
        {
            var card = await _db.AiPersonCards.Where(x => x.PersonId == c.PersonId && x.IsLatest).FirstOrDefaultAsync(ct);
            candidateContexts.Add(new PersonContext(c.PersonId, c.FullName, c.Company?.CompanyName, c.JobTitle, card?.Summary, card?.Issues, card?.IntroducerName));
        }

        var suggestions = await _llm.SuggestRelationsAsync(target, candidateContexts, ct);

        // 既に登録済みの関係は重複提案しない
        var existingRelatedIds = await _db.PersonRelations
            .Where(r => r.FromPersonId == personId || r.ToPersonId == personId)
            .Select(r => r.FromPersonId == personId ? r.ToPersonId : r.FromPersonId)
            .ToListAsync(ct);
        var existingSet = existingRelatedIds.ToHashSet();

        var nameById = candidates.ToDictionary(c => c.PersonId, c => c.FullName);

        var response = suggestions
            .Where(s => !existingSet.Contains(s.RelatedPersonId))
            .Select(s => new RelationSuggestionResponse(s.RelatedPersonId, nameById.GetValueOrDefault(s.RelatedPersonId, "?"), s.RelationType, s.Reason, s.Strength))
            .ToList();

        return Ok(response);
    }

    // F-005/F-006 人脈グラフ: AI提案(または手動)の関係を確定登録する
    [HttpPost("{personId:guid}/relations")]
    public async Task<IActionResult> ConfirmRelations(Guid personId, ConfirmRelationsRequest request, CancellationToken ct)
    {
        var orgId = User.GetOrgId();
        var person = await _db.Persons.FirstOrDefaultAsync(p => p.PersonId == personId && p.OrgId == orgId, ct);
        if (person is null) return NotFound();

        const string note = "利用者が登録（AI提案の確認、または手動追加）";

        foreach (var item in request.Relations)
        {
            var relatedExists = await _db.Persons.AnyAsync(p => p.PersonId == item.RelatedPersonId && p.OrgId == orgId, ct);
            if (!relatedExists) continue;

            await UpsertRelationAsync(orgId, personId, item.RelatedPersonId, item.RelationType, item.Strength, isManual: true, note, ct);

            if (item.IsBidirectional)
            {
                await UpsertRelationAsync(orgId, item.RelatedPersonId, personId, item.RelationType, item.Strength, isManual: true, note, ct);
            }
        }

        await _db.SaveChangesAsync(ct);
        return NoContent();
    }

    // F-005/F-006 人脈グラフ: 指定人物を起点に距離maxDepthまでの関係グラフを取得する（テーブル設計書5.3）
    [HttpGet("{personId:guid}/network")]
    public async Task<ActionResult<NetworkGraphResponse>> GetNetwork(Guid personId, [FromQuery] int maxDepth, CancellationToken ct)
    {
        var orgId = User.GetOrgId();
        var exists = await _db.Persons.AnyAsync(p => p.PersonId == personId && p.OrgId == orgId, ct);
        if (!exists) return NotFound();

        var depth = maxDepth <= 0 ? 2 : maxDepth;
        var graph = await _network.GetNetworkAsync(personId, orgId, depth, ct);

        return Ok(new NetworkGraphResponse(
            graph.Nodes.Select(n => new NetworkNodeResponse(n.PersonId, n.FullName, n.CompanyName, n.IndustryName, n.OccupationName, n.Depth, n.IsSelf)).ToList(),
            graph.Edges.Select(e => new NetworkEdgeResponse(e.RelationId, e.FromPersonId, e.ToPersonId, e.RelationType, e.Strength)).ToList()));
    }

    private async Task<PersonContext?> BuildPersonContextAsync(Guid personId, Guid orgId, CancellationToken ct)
    {
        var person = await _db.Persons.Include(p => p.Company)
            .FirstOrDefaultAsync(p => p.PersonId == personId && p.OrgId == orgId, ct);
        if (person is null) return null;

        var card = await _db.AiPersonCards.Where(c => c.PersonId == personId && c.IsLatest).FirstOrDefaultAsync(ct);
        return new PersonContext(person.PersonId, person.FullName, person.Company?.CompanyName, person.JobTitle, card?.Summary, card?.Issues, card?.IntroducerName);
    }

    private async Task TryLinkIntroducerAsync(Person person, string? introducerName, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(introducerName)) return;

        var matches = await _db.Persons
            .Where(p => p.OrgId == person.OrgId && p.PersonId != person.PersonId)
            .Where(p => EF.Functions.ILike(p.FullName, $"%{introducerName}%"))
            .ToListAsync(ct);

        if (matches.Count != 1) return; // 該当なし・複数一致の場合は誤結線を避けるため自動リンクしない

        await UpsertRelationAsync(person.OrgId, matches[0].PersonId, person.PersonId, "referrer", strength: 3, isManual: false,
            note: "AI推定（人物カルテの紹介者欄より）", ct);
    }

    // 同じ会社の人物同士は person_relations のエッジ（紹介関係）にはせず、カルテのメモに書き添えるだけにする。
    // colleague関係を全員分エッジ化すると大企業で組み合わせ爆発する上、紹介経路探索のノイズにもなるため、
    // 「同僚である」という文脈情報はテキストとして持たせ、AI指示のRAG検索から補足情報として拾えるようにする。
    private async Task AppendColleagueNoteAsync(Guid orgId, Person person, Guid companyId, CancellationToken ct)
    {
        var colleagueNames = await _db.Persons
            .Where(p => p.OrgId == orgId && p.CompanyId == companyId && p.PersonId != person.PersonId)
            .OrderByDescending(p => p.LastContactAt)
            .Select(p => p.FullName)
            .Take(10) // ノートが際限なく長くならないよう上限を設ける
            .ToListAsync(ct);

        if (colleagueNames.Count == 0) return;

        var note = $"社内に {string.Join('、', colleagueNames)} が登録されています。";
        person.Profile!.Note = string.IsNullOrWhiteSpace(person.Profile.Note)
            ? note
            : $"{person.Profile.Note}\n{note}";
    }

    private async Task UpsertRelationAsync(
        Guid orgId, Guid fromPersonId, Guid toPersonId, string relationType, int strength, bool isManual, string? note, CancellationToken ct)
    {
        var existing = await _db.PersonRelations.FirstOrDefaultAsync(r =>
            r.FromPersonId == fromPersonId && r.ToPersonId == toPersonId && r.RelationType == relationType, ct);

        if (existing is not null)
        {
            if (!existing.StrengthIsManual)
            {
                existing.Strength = (short)strength;
            }
            existing.UpdatedBy = User.GetUserId();
            return;
        }

        _db.PersonRelations.Add(new PersonRelation
        {
            RelationId = Guid.NewGuid(),
            OrgId = orgId,
            FromPersonId = fromPersonId,
            ToPersonId = toPersonId,
            RelationType = relationType,
            Strength = (short)strength,
            StrengthIsManual = isManual,
            Note = note,
            CreatedAt = DateTimeOffset.UtcNow,
            CreatedBy = User.GetUserId(),
            UpdatedAt = DateTimeOffset.UtcNow,
            UpdatedBy = User.GetUserId(),
        });
    }

    // F-028: 相互人脈登録。メールアドレスが既存GOENユーザーと完全一致する場合のみ実行し、あいまい一致は行わない。
    // 対象ユーザーがallow_mutual_registrationをOFFにしている場合は何もしない（設定画面でのON/OFF切替、既定はON）。
    private async Task<Guid?> TryCreateMutualRegistrationAsync(string counterpartEmail, Guid registeringUserId, CancellationToken ct)
    {
        var normalizedEmail = counterpartEmail.Trim().ToLowerInvariant();

        var counterpartUser = await _db.Users.FirstOrDefaultAsync(u => u.Email.ToLower() == normalizedEmail, ct);
        if (counterpartUser is null || !counterpartUser.AllowMutualRegistration) return null;
        if (counterpartUser.UserId == registeringUserId) return null; // 自分自身のメールアドレスを入力した場合は何もしない

        var registeringUser = await _db.Users.FirstOrDefaultAsync(u => u.UserId == registeringUserId, ct);
        if (registeringUser is null || string.IsNullOrWhiteSpace(registeringUser.Email)) return null;

        // 既に相手側に自分が登録済みなら重複作成しない
        var alreadyExists = await _db.Persons.AnyAsync(p =>
            p.OrgId == counterpartUser.OrgId && p.OwnerUserId == counterpartUser.UserId &&
            p.Profile != null && p.Profile.Email != null && p.Profile.Email.ToLower() == registeringUser.Email.ToLower(), ct);
        if (alreadyExists) return null;

        var reciprocalPerson = new Person
        {
            PersonId = Guid.NewGuid(),
            OrgId = counterpartUser.OrgId,
            OwnerUserId = counterpartUser.UserId,
            FullName = registeringUser.DisplayName,
            SourceType = "mutual_registration",
            FirstMetAt = DateOnly.FromDateTime(DateTime.UtcNow),
            CreatedAt = DateTimeOffset.UtcNow,
            CreatedBy = counterpartUser.UserId,
            UpdatedAt = DateTimeOffset.UtcNow,
            UpdatedBy = counterpartUser.UserId,
        };
        _db.Persons.Add(reciprocalPerson);

        reciprocalPerson.Profile = new PersonProfile
        {
            PersonId = reciprocalPerson.PersonId,
            Email = registeringUser.Email,
            Note = "相互人脈登録により自動作成されました（相手があなたを名刺登録しました）",
            CreatedAt = DateTimeOffset.UtcNow,
            CreatedBy = counterpartUser.UserId,
            UpdatedAt = DateTimeOffset.UtcNow,
            UpdatedBy = counterpartUser.UserId,
        };

        return reciprocalPerson.PersonId;
    }

    private async Task<Guid> ResolveCompanyAsync(string companyName, CancellationToken ct)
    {
        var normalized = NormalizeCompanyName(companyName);
        var existing = await _db.Companies.FirstOrDefaultAsync(c => c.CompanyNameNormalized == normalized, ct);
        if (existing is not null) return existing.CompanyId;

        var company = new Company
        {
            CompanyId = Guid.NewGuid(),
            CompanyName = companyName,
            CompanyNameNormalized = normalized,
            CreatedAt = DateTimeOffset.UtcNow,
            CreatedBy = User.GetUserId(),
            UpdatedAt = DateTimeOffset.UtcNow,
            UpdatedBy = User.GetUserId(),
        };
        _db.Companies.Add(company);
        return company.CompanyId;
    }

    private static OcrDraftResponse ToUnchangedOcrDraft(RefineOcrDraftRequest request) => new(
        request.FullName, request.FullNameKana, request.CompanyName, request.Department, request.JobTitle,
        request.Tel, request.Mobile, request.Email, request.Address,
        Url: null, Confidence: 0m, SnsLinks: Array.Empty<SnsLink>());

    private static string? GetString(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) || value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
        {
            return null;
        }
        var s = value.GetString();
        return string.IsNullOrWhiteSpace(s) ? null : s;
    }

    private static string NormalizeCompanyName(string name) =>
        name.Replace("株式会社", "").Replace("有限会社", "").Trim();

    // 業種は「人物が選んだ職種に紐づく業種」を優先する（F-030）。会社の業種は入力経路がなく実質未使用のため、
    // 職種が未設定または職種に業種が紐付けられていない場合のみ補助的にフォールバックする（PersonReadSyncServiceと同じ方針）。
    private async Task<string?> GetIndustryNameAsync(Person person, CancellationToken ct)
    {
        var industryCode = person.Occupation?.IndustryCode ?? person.Company?.IndustryCode;
        if (industryCode is null) return null;
        return await _db.Industries.Where(i => i.IndustryCode == industryCode).Select(i => i.IndustryName).FirstOrDefaultAsync(ct);
    }

    private static PersonDetail ToDetail(Person person, AiPersonCard? card, string? industryName)
    {
        var (sourceUrls, sourceFiles) = ParseInputSources(card?.InputSourcesJson);
        return new(
            person.PersonId, person.FullName, person.FullNameKana, person.Department, person.JobTitle,
            person.OccupationCode, person.Occupation?.OccupationName, industryName,
            person.CompanyId, person.Company?.CompanyName,
            person.Visibility, person.FirstMetAt, person.MetPlace, person.LastContactAt, person.SourceType,
            person.Profile?.Tel, person.Profile?.Mobile, person.Profile?.Email, person.Profile?.Address, person.Profile?.Note,
            ParseSnsLinks(person.Profile?.SnsAccountsJson),
            card?.Summary, card?.Business, card?.Issues, card?.Hobby,
            person.IntroducerPersonId, person.IntroducerPerson?.FullName,
            sourceUrls, sourceFiles, card?.InputContactIds.Length ?? 0);
    }

    // F-032: AI要約生成時に参照したHPリンク・資料ファイル（InputSourcesJson）を、カルテ画面表示用にURL/ファイル名へ分離する
    private static (IReadOnlyList<string> Urls, IReadOnlyList<string> Files) ParseInputSources(string? inputSourcesJson)
    {
        if (string.IsNullOrWhiteSpace(inputSourcesJson))
        {
            return (Array.Empty<string>(), Array.Empty<string>());
        }

        try
        {
            using var doc = JsonDocument.Parse(inputSourcesJson);
            if (doc.RootElement.ValueKind != JsonValueKind.Array)
            {
                return (Array.Empty<string>(), Array.Empty<string>());
            }

            var urls = new List<string>();
            var files = new List<string>();
            foreach (var item in doc.RootElement.EnumerateArray())
            {
                var type = item.TryGetProperty("type", out var t) ? t.GetString() : null;
                var value = item.TryGetProperty("value", out var v) ? v.GetString() : null;
                if (string.IsNullOrWhiteSpace(value)) continue;
                if (type == "url") urls.Add(value);
                else if (type == "file") files.Add(value);
            }
            return (urls, files);
        }
        catch (JsonException)
        {
            return (Array.Empty<string>(), Array.Empty<string>());
        }
    }

    private static IReadOnlyList<SnsLink> ParseSnsLinks(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return Array.Empty<SnsLink>();
        try
        {
            return JsonSerializer.Deserialize<List<SnsLink>>(json) ?? new List<SnsLink>();
        }
        catch (JsonException)
        {
            return Array.Empty<SnsLink>(); // 旧形式（オブジェクト）等、解析できない値は空扱いにする
        }
    }
}
