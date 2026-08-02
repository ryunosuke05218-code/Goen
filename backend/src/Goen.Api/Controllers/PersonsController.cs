using Goen.Api.Dtos;
using Goen.Domain.Entities;
using Goen.Infrastructure.ExternalAi;
using Goen.Infrastructure.Persistence;
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
    private readonly NetworkGraphService _network;
    private readonly RagIndexQueueService _ragQueue;
    private readonly IOcrService _ocr;
    private readonly ISpeechToTextService _asr;
    private readonly ILlmService _llm;
    private readonly AiChatOptions _aiOptions;

    public PersonsController(
        GoenDbContext db,
        PersonReadSyncService readSync,
        NetworkGraphService network,
        RagIndexQueueService ragQueue,
        IOcrService ocr,
        ISpeechToTextService asr,
        ILlmService llm,
        IOptions<AiChatOptions> aiOptions)
    {
        _db = db;
        _readSync = readSync;
        _network = network;
        _ragQueue = ragQueue;
        _ocr = ocr;
        _asr = asr;
        _llm = llm;
        _aiOptions = aiOptions.Value;
    }

    // F-004（簡易版）: persons_read への氏名・要約の部分一致検索。曖昧検索（RAG）は将来のフェーズで拡張する。
    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<PersonListItem>>> List([FromQuery] string? q, CancellationToken ct)
    {
        var orgId = User.GetOrgId();
        var query = _db.PersonsRead.Where(r => r.OrgId == orgId);

        if (!string.IsNullOrWhiteSpace(q))
        {
            query = query.Where(r => EF.Functions.ILike(r.SearchText, $"%{q}%"));
        }

        var items = await query
            .OrderByDescending(r => r.Importance)
            .ThenByDescending(r => r.LastContactAt)
            .Select(r => new PersonListItem(
                r.PersonId, r.FullName, r.FullNameKana, r.CompanyName, r.JobTitle,
                r.Importance, r.Summary, r.LastContactAt, r.ContactCount))
            .ToListAsync(ct);

        return Ok(items);
    }

    [HttpGet("{personId:guid}")]
    public async Task<ActionResult<PersonDetail>> Get(Guid personId, CancellationToken ct)
    {
        var person = await _db.Persons
            .Include(p => p.Company)
            .Include(p => p.Profile)
            .Include(p => p.IntroducerPerson)
            .FirstOrDefaultAsync(p => p.PersonId == personId && p.OrgId == User.GetOrgId(), ct);

        if (person is null) return NotFound();

        var latestCard = await _db.AiPersonCards
            .Where(c => c.PersonId == personId && c.IsLatest)
            .FirstOrDefaultAsync(ct);

        return Ok(ToDetail(person, latestCard));
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
            SourceType = request.SourceType,
            IntroducerPersonId = introducerPersonId,
            FirstMetAt = DateOnly.FromDateTime(DateTime.UtcNow),
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

        await _db.SaveChangesAsync(ct);
        await _readSync.RefreshAsync(person.PersonId, ct);
        await _ragQueue.EnqueueAsync("profile", person.PersonId, person.PersonId, 'U', ct);
        if (introducerPersonId is not null)
        {
            await _readSync.RefreshAsync(introducerPersonId.Value, ct);
        }

        var created = await _db.Persons
            .Include(p => p.Company)
            .Include(p => p.Profile)
            .Include(p => p.IntroducerPerson)
            .FirstAsync(p => p.PersonId == person.PersonId, ct);

        return CreatedAtAction(nameof(Get), new { personId = person.PersonId }, ToDetail(created, null));
    }

    [HttpPut("{personId:guid}")]
    public async Task<ActionResult<PersonDetail>> Update(Guid personId, UpdatePersonRequest request, CancellationToken ct)
    {
        var person = await _db.Persons
            .Include(p => p.Profile)
            .Include(p => p.Company)
            .Include(p => p.IntroducerPerson)
            .FirstOrDefaultAsync(p => p.PersonId == personId && p.OrgId == User.GetOrgId(), ct);
        if (person is null) return NotFound();

        person.FullName = request.FullName;
        person.FullNameKana = request.FullNameKana;
        person.Department = request.Department;
        person.JobTitle = request.JobTitle;
        person.Importance = request.Importance;
        person.ImportanceIsManual = request.ImportanceIsManual; // F-022: 手動上書き時はAI自動算出で以後上書きしない
        person.Visibility = request.Visibility;
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
        person.Profile.UpdatedBy = User.GetUserId();

        await _db.SaveChangesAsync(ct);
        await _readSync.RefreshAsync(personId, ct);
        await _ragQueue.EnqueueAsync("profile", personId, personId, 'U', ct);

        var latestCard = await _db.AiPersonCards.FirstOrDefaultAsync(c => c.PersonId == personId && c.IsLatest, ct);
        return Ok(ToDetail(person, latestCard));
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
    [HttpPost("ocr-draft")]
    [RequestSizeLimit(10_000_000)]
    public async Task<ActionResult<OcrDraftResponse>> OcrDraft(IFormFile image, CancellationToken ct)
    {
        await using var stream = image.OpenReadStream();
        var result = await _ocr.ExtractAsync(stream, ct);

        return Ok(new OcrDraftResponse(
            result.FullName, result.FullNameKana, result.CompanyName, result.Department, result.JobTitle,
            result.Tel, result.Mobile, result.Email, result.Address, result.Url, result.Confidence));
    }

    // F-011: 接点履歴の登録
    [HttpPost("{personId:guid}/contacts")]
    public async Task<ActionResult<ContactItem>> AddContact(Guid personId, CreateContactRequest request, CancellationToken ct)
    {
        var person = await _db.Persons.FirstOrDefaultAsync(p => p.PersonId == personId && p.OrgId == User.GetOrgId(), ct);
        if (person is null) return NotFound();

        var contact = new Contact
        {
            ContactId = Guid.NewGuid(),
            OrgId = person.OrgId,
            PersonId = personId,
            UserId = User.GetUserId(),
            ContactType = request.ContactType,
            OccurredAt = request.OccurredAt,
            Place = request.Place,
            Note = request.Note,
            CreatedAt = DateTimeOffset.UtcNow,
            CreatedBy = User.GetUserId(),
            UpdatedAt = DateTimeOffset.UtcNow,
            UpdatedBy = User.GetUserId(),
        };
        _db.Contacts.Add(contact);

        if (person.LastContactAt is null || request.OccurredAt > person.LastContactAt)
        {
            person.LastContactAt = request.OccurredAt;
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

    // F-010: 蓄積された接点・文字起こしからAI人物カルテを生成する
    [HttpPost("{personId:guid}/cards/generate")]
    public async Task<ActionResult<GenerateCardResponse>> GenerateCard(Guid personId, CancellationToken ct)
    {
        var person = await _db.Persons.FirstOrDefaultAsync(p => p.PersonId == personId && p.OrgId == User.GetOrgId(), ct);
        if (person is null) return NotFound();

        var sourceTexts = await _db.Transcripts
            .Where(t => t.Contact.PersonId == personId)
            .OrderByDescending(t => t.CreatedAt)
            .Select(t => t.Content)
            .Take(20)
            .ToListAsync(ct);

        var contactIds = await _db.Contacts
            .Where(c => c.PersonId == personId)
            .Select(c => c.ContactId)
            .ToArrayAsync(ct);

        var draft = await _llm.GeneratePersonCardAsync(person.FullName, sourceTexts, ct);

        var previousGeneration = await _db.AiPersonCards
            .Where(c => c.PersonId == personId)
            .OrderByDescending(c => c.Generation)
            .Select(c => (int?)c.Generation)
            .FirstOrDefaultAsync(ct) ?? 0;

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
            graph.Nodes.Select(n => new NetworkNodeResponse(n.PersonId, n.FullName, n.CompanyName, n.Importance, n.Depth, n.IsSelf)).ToList(),
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

    private static string NormalizeCompanyName(string name) =>
        name.Replace("株式会社", "").Replace("有限会社", "").Trim();

    private static PersonDetail ToDetail(Person person, AiPersonCard? card) => new(
        person.PersonId, person.FullName, person.FullNameKana, person.Department, person.JobTitle,
        person.CompanyId, person.Company?.CompanyName, person.Importance, person.ImportanceIsManual,
        person.Visibility, person.FirstMetAt, person.LastContactAt, person.SourceType,
        person.Profile?.Tel, person.Profile?.Mobile, person.Profile?.Email, person.Profile?.Address, person.Profile?.Note,
        card?.Summary, card?.Business, card?.Issues, card?.Hobby,
        person.IntroducerPersonId, person.IntroducerPerson?.FullName);
}
