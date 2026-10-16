using System.Data.Common;
using LibraryApp.Data;
using LibraryApp.Domain;

namespace LibraryApp.Repositories;

public sealed class FineRepository : RepositoryBase, IFineRepository
{
    private const string SelectFines =
        "SELECT fine_id, member_id, member_name, loan_id, amount, reason, status, issued_at, paid_at FROM v_fines";

    public FineRepository(DbSession session) : base(session)
    {
    }

    public Task<Fine?> GetByIdAsync(int id, CancellationToken ct = default) =>
        QuerySingleOrDefaultAsync(SelectFines + " WHERE fine_id = @id", Map, ct, P("id", id));

    public Task<IReadOnlyList<Fine>> GetAllAsync(CancellationToken ct = default) =>
        QueryAsync(SelectFines + " ORDER BY issued_at DESC", Map, ct);

    public Task<IReadOnlyList<Fine>> GetByMemberAsync(int memberId, bool onlyUnpaid = false, CancellationToken ct = default) =>
        QueryAsync(
            SelectFines + " WHERE member_id = @id AND (NOT @only_unpaid OR status = 'unpaid') ORDER BY issued_at DESC",
            Map,
            ct,
            P("id", memberId),
            P("only_unpaid", onlyUnpaid));

    public async Task<int> PayAsync(int fineId, PaymentMethod method, CancellationToken ct = default)
    {
        var row = await CallAsync(
            "CALL sp_fine_pay(@id, @method::library.payment_method, NULL)",
            ct,
            P("id", fineId),
            P("method", method));

        return ToInt(row[0]);
    }

    public Task WaiveAsync(int fineId, string comment, CancellationToken ct = default) =>
        ExecuteAsync("CALL sp_fine_waive(@id, @comment)", ct, P("id", fineId), P("comment", comment));

    private static Fine Map(DbDataReader r) => new(
        r.GetInt("fine_id"),
        r.GetInt("member_id"),
        r.GetText("member_name"),
        r.GetNullableInt("loan_id"),
        r.GetMoney("amount"),
        r.GetText("reason"),
        r.GetEnum<FineStatus>("status"),
        r.GetTimestamp("issued_at"),
        r.GetNullableTimestamp("paid_at"));
}
