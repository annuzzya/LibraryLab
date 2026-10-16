using System.Data.Common;
using LibraryApp.Data;
using LibraryApp.Domain;

namespace LibraryApp.Repositories;

public sealed class MemberRepository : RepositoryBase, IMemberRepository
{
    private const string SelectMembers =
        "SELECT member_id, card_number, first_name, last_name, birth_date, email, phone, address, registered_at, " +
        "plan_name, membership_until, active_loans, debt, updated_at, updated_by_login FROM v_members";

    public MemberRepository(DbSession session) : base(session)
    {
    }

    public Task<Member?> GetByIdAsync(int id, CancellationToken ct = default) =>
        QuerySingleOrDefaultAsync(SelectMembers + " WHERE member_id = @id", Map, ct, P("id", id));

    public Task<Member?> GetByCardNumberAsync(string cardNumber, CancellationToken ct = default) =>
        QuerySingleOrDefaultAsync(SelectMembers + " WHERE card_number = @card", Map, ct, P("card", cardNumber));

    public Task<IReadOnlyList<Member>> GetAllAsync(CancellationToken ct = default) =>
        QueryAsync(SelectMembers + " ORDER BY last_name, first_name", Map, ct);

    public Task<IReadOnlyList<ArchivedMember>> GetArchivedAsync(CancellationToken ct = default) =>
        QueryAsync(
            "SELECT member_id, card_number, full_name, email, deleted_at, deleted_by_login FROM v_members_archive ORDER BY deleted_at DESC",
            r => new ArchivedMember(
                r.GetInt("member_id"),
                r.GetText("card_number"),
                r.GetText("full_name"),
                r.GetText("email"),
                r.GetTimestamp("deleted_at"),
                r.GetNullableText("deleted_by_login")),
            ct);

    public async Task<(int Id, string CardNumber)> RegisterAsync(NewMember member, CancellationToken ct = default)
    {
        var row = await CallAsync(
            "CALL sp_member_register(@first_name, @last_name, @email, @phone, @birth_date, @address, NULL, NULL)",
            ct,
            P("first_name", member.FirstName),
            P("last_name", member.LastName),
            P("email", member.Email),
            P("phone", member.Phone),
            P("birth_date", member.BirthDate),
            P("address", member.Address));

        return (ToInt(row[0]), (string)row[1]!);
    }

    public Task UpdateAsync(int memberId, MemberChanges changes, CancellationToken ct = default) =>
        ExecuteAsync(
            "CALL sp_member_update(@id, @first_name, @last_name, @email, @phone, @address)",
            ct,
            P("id", memberId),
            P("first_name", changes.FirstName),
            P("last_name", changes.LastName),
            P("email", changes.Email),
            P("phone", changes.Phone),
            P("address", changes.Address));

    public Task SoftDeleteAsync(int memberId, CancellationToken ct = default) =>
        ExecuteAsync("CALL sp_member_soft_delete(@id)", ct, P("id", memberId));

    public Task RestoreAsync(int memberId, CancellationToken ct = default) =>
        ExecuteAsync("CALL sp_member_restore(@id)", ct, P("id", memberId));

    public async Task<MembershipReceipt> PurchaseMembershipAsync(int memberId, int planId, int months, PaymentMethod method, CancellationToken ct = default)
    {
        var row = await CallAsync(
            "CALL sp_membership_purchase(@member_id, @plan_id, @months, @method::library.payment_method, NULL, NULL)",
            ct,
            P("member_id", memberId),
            P("plan_id", planId),
            P("months", months),
            P("method", method));

        return new MembershipReceipt(ToInt(row[0]), ToDate(row[1]));
    }

    private static Member Map(DbDataReader r) => new(
        r.GetInt("member_id"),
        r.GetText("card_number"),
        r.GetText("first_name"),
        r.GetText("last_name"),
        r.GetNullableDate("birth_date"),
        r.GetText("email"),
        r.GetNullableText("phone"),
        r.GetNullableText("address"),
        r.GetTimestamp("registered_at"),
        r.GetNullableText("plan_name"),
        r.GetNullableDate("membership_until"),
        r.GetInt("active_loans"),
        r.GetMoney("debt"),
        r.GetTimestamp("updated_at"),
        r.GetNullableText("updated_by_login"));
}
