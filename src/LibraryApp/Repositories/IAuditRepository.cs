using LibraryApp.Domain;

namespace LibraryApp.Repositories;

public interface IAuditRepository
{
    Task<IReadOnlyList<AuditEntry>> GetForRecordAsync(string table, int recordId, CancellationToken ct = default);

    Task<IReadOnlyList<AuditEntry>> GetLatestAsync(int count = 10, CancellationToken ct = default);
}
