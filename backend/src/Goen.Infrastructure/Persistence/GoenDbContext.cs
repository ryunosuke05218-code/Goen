using Goen.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace Goen.Infrastructure.Persistence;

// スキーマの正本は db/ddl_goen_v1.0.sql（テーブル設計書_GOEN_v1.0.md準拠）。
// このDbContextはそのスキーマへマッピングするのみで、マイグレーションによるスキーマ作成は行わない。
public class GoenDbContext : DbContext
{
    public GoenDbContext(DbContextOptions<GoenDbContext> options) : base(options)
    {
    }

    public DbSet<Organization> Organizations => Set<Organization>();
    public DbSet<User> Users => Set<User>();
    public DbSet<Company> Companies => Set<Company>();
    public DbSet<Person> Persons => Set<Person>();
    public DbSet<PersonProfile> PersonProfiles => Set<PersonProfile>();
    public DbSet<Contact> Contacts => Set<Contact>();
    public DbSet<ContactMedia> ContactMedia => Set<ContactMedia>();
    public DbSet<Transcript> Transcripts => Set<Transcript>();
    public DbSet<AiPersonCard> AiPersonCards => Set<AiPersonCard>();
    public DbSet<NextAction> NextActions => Set<NextAction>();
    public DbSet<PersonRead> PersonsRead => Set<PersonRead>();
    public DbSet<AuthToken> AuthTokens => Set<AuthToken>();
    public DbSet<PersonRelation> PersonRelations => Set<PersonRelation>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Organization>(e =>
        {
            e.ToTable("organizations");
            e.HasKey(x => x.OrgId);
            e.Property(x => x.Version).HasDefaultValue(1);
            e.HasMany(x => x.Users).WithOne(x => x.Organization).HasForeignKey(x => x.OrgId);
        });

        modelBuilder.Entity<User>(e =>
        {
            e.ToTable("users");
            e.HasKey(x => x.UserId);
            e.Property(x => x.Version).HasDefaultValue(1);
            e.HasIndex(x => x.Email).IsUnique(); // DB側は lower(email) の関数一意索引（ux_users_email）と併用
        });

        modelBuilder.Entity<Company>(e =>
        {
            e.ToTable("companies");
            e.HasKey(x => x.CompanyId);
            e.Property(x => x.Version).HasDefaultValue(1);
        });

        modelBuilder.Entity<Person>(e =>
        {
            e.ToTable("persons");
            e.HasKey(x => x.PersonId);
            e.Property(x => x.Version).HasDefaultValue(1);
            e.HasOne(x => x.Company).WithMany().HasForeignKey(x => x.CompanyId);
            e.HasOne(x => x.IntroducerPerson).WithMany().HasForeignKey(x => x.IntroducerPersonId).OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Profile).WithOne(x => x.Person).HasForeignKey<PersonProfile>(x => x.PersonId);
            e.HasMany(x => x.Contacts).WithOne(x => x.Person).HasForeignKey(x => x.PersonId);
            e.HasMany(x => x.Cards).WithOne(x => x.Person).HasForeignKey(x => x.PersonId);
            e.HasMany(x => x.NextActions).WithOne(x => x.Person).HasForeignKey(x => x.PersonId);
        });

        modelBuilder.Entity<PersonProfile>(e =>
        {
            e.ToTable("person_profiles");
            e.HasKey(x => x.PersonId);
            e.Property(x => x.SnsAccountsJson).HasColumnName("sns_accounts").HasColumnType("jsonb");
            e.Property(x => x.Version).HasDefaultValue(1);
        });

        modelBuilder.Entity<Contact>(e =>
        {
            e.ToTable("contacts");
            e.HasKey(x => x.ContactId);
            e.Property(x => x.Version).HasDefaultValue(1);
            e.HasMany(x => x.Media).WithOne(x => x.Contact).HasForeignKey(x => x.ContactId);
            e.HasMany(x => x.Transcripts).WithOne(x => x.Contact).HasForeignKey(x => x.ContactId);
        });

        modelBuilder.Entity<ContactMedia>(e =>
        {
            e.ToTable("contact_media");
            e.HasKey(x => x.MediaId);
            e.Property(x => x.OcrRawJson).HasColumnName("ocr_raw").HasColumnType("jsonb");
            e.Property(x => x.Version).HasDefaultValue(1);
        });

        modelBuilder.Entity<Transcript>(e =>
        {
            e.ToTable("transcripts");
            e.HasKey(x => x.TranscriptId);
            e.Property(x => x.Version).HasDefaultValue(1);
        });

        modelBuilder.Entity<AiPersonCard>(e =>
        {
            e.ToTable("ai_person_cards");
            e.HasKey(x => x.CardId);
            e.Property(x => x.FieldSourcesJson).HasColumnName("field_sources").HasColumnType("jsonb");
            e.Property(x => x.InputContactIds).HasColumnName("input_contact_ids").HasColumnType("uuid[]");
            e.Property(x => x.Version).HasDefaultValue(1);
        });

        modelBuilder.Entity<NextAction>(e =>
        {
            e.ToTable("next_actions");
            e.HasKey(x => x.ActionId);
            e.Property(x => x.Version).HasDefaultValue(1);
        });

        modelBuilder.Entity<PersonRead>(e =>
        {
            e.ToTable("persons_read");
            e.HasKey(x => x.PersonId);
            e.Property(x => x.TagsJson).HasColumnName("tags").HasColumnType("jsonb");
            e.Property(x => x.OpenActionJson).HasColumnName("open_action").HasColumnType("jsonb");
        });

        modelBuilder.Entity<AuthToken>(e =>
        {
            e.ToTable("auth_tokens");
            e.HasKey(x => x.TokenId);
            e.Property(x => x.DeviceInfoJson).HasColumnName("device_info").HasColumnType("jsonb");
        });

        modelBuilder.Entity<PersonRelation>(e =>
        {
            e.ToTable("person_relations");
            e.HasKey(x => x.RelationId);
            e.Property(x => x.Version).HasDefaultValue(1);
            e.HasIndex(x => new { x.FromPersonId, x.ToPersonId, x.RelationType }).IsUnique();
        });
    }
}
