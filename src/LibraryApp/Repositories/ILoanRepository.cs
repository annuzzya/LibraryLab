using LibraryApp.Domain;

namespace LibraryApp.Repositories;

public interface ILoanRepository : IReadRepository<Loan, int>
{
    Task<IReadOnlyList<Loan>> GetActiveByMemberAsync(int memberId, CancellationToken ct = default);

    Task<IReadOnlyList<Loan>> GetHistoryByMemberAsync(int memberId, CancellationToken ct = default);

    Task<IReadOnlyList<Loan>> GetOverdueAsync(CancellationToken ct = default);

    Task<LoanReceipt> IssueAsync(int memberId, int copyId, CancellationToken ct = default);

    Task<ReturnResult> ReturnAsync(int loanId, CancellationToken ct = default);

    Task<DateOnly> ExtendAsync(int loanId, int days = 7, CancellationToken ct = default);

    Task<int> MarkOverdueAsync(CancellationToken ct = default);
}
