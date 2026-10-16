using System.Data.Common;
using LibraryApp.Data;
using LibraryApp.Domain;

namespace LibraryApp.Repositories;

public sealed class LoanRepository : RepositoryBase, ILoanRepository
{
    private const string Columns =
        "SELECT loan_id, member_id, card_number, member_name, copy_id, inventory_code, book_id, title, branch_name, " +
        "loan_date, due_date, return_date, extensions, status, days_overdue, fine_estimate ";

    public LoanRepository(DbSession session) : base(session)
    {
    }

    public Task<Loan?> GetByIdAsync(int id, CancellationToken ct = default) =>
        QuerySingleOrDefaultAsync(Columns + "FROM v_loans WHERE loan_id = @id", Map, ct, P("id", id));

    public Task<IReadOnlyList<Loan>> GetAllAsync(CancellationToken ct = default) =>
        QueryAsync(Columns + "FROM v_loans ORDER BY loan_date DESC", Map, ct);

    public Task<IReadOnlyList<Loan>> GetActiveByMemberAsync(int memberId, CancellationToken ct = default) =>
        QueryAsync(Columns + "FROM v_active_loans WHERE member_id = @id ORDER BY due_date", Map, ct, P("id", memberId));

    public Task<IReadOnlyList<Loan>> GetHistoryByMemberAsync(int memberId, CancellationToken ct = default) =>
        QueryAsync(Columns + "FROM v_loans WHERE member_id = @id ORDER BY loan_date DESC", Map, ct, P("id", memberId));

    public Task<IReadOnlyList<Loan>> GetOverdueAsync(CancellationToken ct = default) =>
        QueryAsync(Columns + "FROM v_overdue_loans ORDER BY days_overdue DESC", Map, ct);

    public async Task<LoanReceipt> IssueAsync(int memberId, int copyId, CancellationToken ct = default)
    {
        var row = await CallAsync(
            "CALL sp_loan_issue(@member_id, @copy_id, NULL, NULL)",
            ct,
            P("member_id", memberId),
            P("copy_id", copyId));

        return new LoanReceipt(ToInt(row[0]), copyId, ToDate(row[1]));
    }

    public async Task<ReturnResult> ReturnAsync(int loanId, CancellationToken ct = default)
    {
        var row = await CallAsync("CALL sp_loan_return(@id, NULL, NULL)", ct, P("id", loanId));
        return new ReturnResult(loanId, ToNullableInt(row[0]), ToDecimal(row[1]));
    }

    public async Task<DateOnly> ExtendAsync(int loanId, int days = 7, CancellationToken ct = default)
    {
        var row = await CallAsync("CALL sp_loan_extend(@id, @days, NULL)", ct, P("id", loanId), P("days", days));
        return ToDate(row[0]);
    }

    public async Task<int> MarkOverdueAsync(CancellationToken ct = default)
    {
        var row = await CallAsync("CALL sp_mark_overdue_loans(NULL)", ct);
        return ToInt(row[0]);
    }

    private static Loan Map(DbDataReader r) => new(
        r.GetInt("loan_id"),
        r.GetInt("member_id"),
        r.GetText("card_number"),
        r.GetText("member_name"),
        r.GetInt("copy_id"),
        r.GetText("inventory_code"),
        r.GetInt("book_id"),
        r.GetText("title"),
        r.GetText("branch_name"),
        r.GetTimestamp("loan_date"),
        r.GetDate("due_date"),
        r.GetNullableTimestamp("return_date"),
        r.GetInt("extensions"),
        r.GetEnum<LoanStatus>("status"),
        r.GetInt("days_overdue"),
        r.GetMoney("fine_estimate"));
}
