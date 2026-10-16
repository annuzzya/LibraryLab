using LibraryApp.Repositories;

namespace LibraryApp.Data;

public interface IUnitOfWork : IAsyncDisposable
{
    int StaffId { get; }

    IMemberRepository Members { get; }

    IBookRepository Books { get; }

    ILoanRepository Loans { get; }

    IFineRepository Fines { get; }

    IAuditRepository Audit { get; }

    Task CommitAsync(CancellationToken ct = default);

    Task RollbackAsync(CancellationToken ct = default);
}

public interface IUnitOfWorkFactory
{
    Task<IUnitOfWork> BeginAsync(int staffId, CancellationToken ct = default);
}
