using System.Data;
using System.Data.Common;
using LibraryApp.Repositories;

namespace LibraryApp.Data;

public sealed class UnitOfWork : IUnitOfWork
{
    private readonly DbSession _session;
    private IMemberRepository? _members;
    private IBookRepository? _books;
    private ILoanRepository? _loans;
    private IFineRepository? _fines;
    private IAuditRepository? _audit;
    private bool _completed;
    private bool _disposed;

    private UnitOfWork(DbSession session, int staffId)
    {
        _session = session;
        StaffId = staffId;
    }

    public int StaffId { get; }

    public IMemberRepository Members => _members ??= new MemberRepository(Session);

    public IBookRepository Books => _books ??= new BookRepository(Session);

    public ILoanRepository Loans => _loans ??= new LoanRepository(Session);

    public IFineRepository Fines => _fines ??= new FineRepository(Session);

    public IAuditRepository Audit => _audit ??= new AuditRepository(Session);

    private DbSession Session
    {
        get
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (_completed)
            {
                throw new InvalidOperationException("Unit of work has already been completed");
            }
            return _session;
        }
    }

    internal static async Task<UnitOfWork> StartAsync(DbConnection connection, int staffId, CancellationToken ct)
    {
        DbTransaction? transaction = null;
        try
        {
            await connection.OpenAsync(ct);
            transaction = await connection.BeginTransactionAsync(IsolationLevel.ReadCommitted, ct);

            var session = new DbSession(connection, transaction);
            await using (var command = session.CreateCommand("CALL sp_set_session_staff(@staff_id)", new[] { new DbParam("staff_id", staffId) }))
            {
                await command.ExecuteNonQueryAsync(ct);
            }

            return new UnitOfWork(session, staffId);
        }
        catch (DbException ex)
        {
            await CleanupAsync(connection, transaction);
            throw DbErrorTranslator.Translate(ex);
        }
        catch
        {
            await CleanupAsync(connection, transaction);
            throw;
        }
    }

    public async Task CommitAsync(CancellationToken ct = default)
    {
        var session = Session;
        try
        {
            await session.Transaction.CommitAsync(ct);
        }
        catch (DbException ex)
        {
            throw DbErrorTranslator.Translate(ex);
        }
        finally
        {
            _completed = true;
        }
    }

    public async Task RollbackAsync(CancellationToken ct = default)
    {
        if (_completed || _disposed)
        {
            return;
        }

        try
        {
            await _session.Transaction.RollbackAsync(ct);
        }
        finally
        {
            _completed = true;
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed)
        {
            return;
        }

        if (!_completed)
        {
            try
            {
                await _session.Transaction.RollbackAsync();
            }
            catch (DbException)
            {
            }
        }

        _disposed = true;
        await CleanupAsync(_session.Connection, _session.Transaction);
    }

    private static async Task CleanupAsync(DbConnection connection, DbTransaction? transaction)
    {
        if (transaction is not null)
        {
            await transaction.DisposeAsync();
        }
        await connection.DisposeAsync();
    }
}

public sealed class UnitOfWorkFactory : IUnitOfWorkFactory
{
    private readonly IConnectionFactory _connections;

    public UnitOfWorkFactory(IConnectionFactory connections)
    {
        _connections = connections;
    }

    public async Task<IUnitOfWork> BeginAsync(int staffId, CancellationToken ct = default) =>
        await UnitOfWork.StartAsync(_connections.Create(), staffId, ct);
}
