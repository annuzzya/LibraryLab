using LibraryApp.Data;
using LibraryApp.Domain;

namespace LibraryApp.Services;

public sealed record MemberCard(Member Member, IReadOnlyList<Loan> ActiveLoans, IReadOnlyList<Fine> Fines);

public sealed record CheckInResult(ReturnResult Return, int? PaymentId);

public sealed class LibraryService
{
    private readonly IUnitOfWorkFactory _uowFactory;

    public LibraryService(IUnitOfWorkFactory uowFactory)
    {
        _uowFactory = uowFactory;
    }

    public async Task<Member> RegisterReaderAsync(
        int staffId,
        NewMember reader,
        int planId,
        int months,
        PaymentMethod method,
        CancellationToken ct = default)
    {
        await using var uow = await _uowFactory.BeginAsync(staffId, ct);

        var (memberId, _) = await uow.Members.RegisterAsync(reader, ct);
        await uow.Members.PurchaseMembershipAsync(memberId, planId, months, method, ct);
        var member = await uow.Members.GetByIdAsync(memberId, ct)
                     ?? throw new LibraryException(LibraryErrorKind.NotFound, $"Читача {memberId} не знайдено");

        await uow.CommitAsync(ct);
        return member;
    }

    public async Task<IReadOnlyList<LoanReceipt>> IssueBooksAsync(
        int staffId,
        int memberId,
        IReadOnlyCollection<string> inventoryCodes,
        CancellationToken ct = default)
    {
        if (inventoryCodes.Count == 0)
        {
            throw new ArgumentException("Не вказано жодного примірника", nameof(inventoryCodes));
        }

        await using var uow = await _uowFactory.BeginAsync(staffId, ct);

        _ = await uow.Members.GetByIdAsync(memberId, ct)
            ?? throw new LibraryException(LibraryErrorKind.NotFound, $"Читача {memberId} не знайдено");

        var receipts = new List<LoanReceipt>(inventoryCodes.Count);
        foreach (var code in inventoryCodes)
        {
            var copy = await uow.Books.GetCopyByInventoryCodeAsync(code, ct)
                       ?? throw new LibraryException(LibraryErrorKind.NotFound, $"Примірник {code} не знайдено");

            receipts.Add(await uow.Loans.IssueAsync(memberId, copy.Id, ct));
        }

        await uow.CommitAsync(ct);
        return receipts;
    }

    public async Task<CheckInResult> ReturnBookAsync(
        int staffId,
        int loanId,
        PaymentMethod? payFineWith,
        CancellationToken ct = default)
    {
        await using var uow = await _uowFactory.BeginAsync(staffId, ct);

        var result = await uow.Loans.ReturnAsync(loanId, ct);

        int? paymentId = null;
        if (result.FineId is int fineId && payFineWith is PaymentMethod method)
        {
            paymentId = await uow.Fines.PayAsync(fineId, method, ct);
        }

        await uow.CommitAsync(ct);
        return new CheckInResult(result, paymentId);
    }

    public async Task<DateOnly> ExtendLoanAsync(int staffId, int loanId, int days, CancellationToken ct = default)
    {
        await using var uow = await _uowFactory.BeginAsync(staffId, ct);
        var dueDate = await uow.Loans.ExtendAsync(loanId, days, ct);
        await uow.CommitAsync(ct);
        return dueDate;
    }

    public async Task SettleDebtsAsync(int staffId, int memberId, PaymentMethod method, CancellationToken ct = default)
    {
        await using var uow = await _uowFactory.BeginAsync(staffId, ct);

        var unpaid = await uow.Fines.GetByMemberAsync(memberId, onlyUnpaid: true, ct);
        foreach (var fine in unpaid)
        {
            await uow.Fines.PayAsync(fine.Id, method, ct);
        }

        await uow.CommitAsync(ct);
    }

    public async Task RemoveReaderAsync(int staffId, int memberId, CancellationToken ct = default)
    {
        await using var uow = await _uowFactory.BeginAsync(staffId, ct);
        await uow.Members.SoftDeleteAsync(memberId, ct);
        await uow.CommitAsync(ct);
    }

    public async Task RestoreReaderAsync(int staffId, int memberId, CancellationToken ct = default)
    {
        await using var uow = await _uowFactory.BeginAsync(staffId, ct);
        await uow.Members.RestoreAsync(memberId, ct);
        await uow.CommitAsync(ct);
    }

    public async Task<MemberCard> GetMemberCardAsync(int staffId, int memberId, CancellationToken ct = default)
    {
        await using var uow = await _uowFactory.BeginAsync(staffId, ct);

        var member = await uow.Members.GetByIdAsync(memberId, ct)
                     ?? throw new LibraryException(LibraryErrorKind.NotFound, $"Читача {memberId} не знайдено");
        var loans = await uow.Loans.GetActiveByMemberAsync(memberId, ct);
        var fines = await uow.Fines.GetByMemberAsync(memberId, ct: ct);

        return new MemberCard(member, loans, fines);
    }
}
