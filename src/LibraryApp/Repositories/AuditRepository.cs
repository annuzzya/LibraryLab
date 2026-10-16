using System.Data.Common;
using LibraryApp.Data;
using LibraryApp.Domain;

namespace LibraryApp.Repositories;

public sealed class AuditRepository : RepositoryBase, IAuditRepository
{
    private const string SelectAudit =
        "SELECT audit_id, table_name, record_id, operation, changed_at, changed_by_login, changes::text AS changes FROM v_audit_trail";

    public AuditRepository(DbSession session) : base(session)
    {
    }

    public Task<IReadOnlyList<AuditEntry>> GetForRecordAsync(string table, int recordId, CancellationToken ct = default) =>
        QueryAsync(
            SelectAudit + " WHERE table_name = @table AND record_id = @id ORDER BY audit_id",
            Map,
            ct,
            P("table", table),
            P("id", recordId));

    public Task<IReadOnlyList<AuditEntry>> GetLatestAsync(int count = 10, CancellationToken ct = default) =>
        QueryAsync(SelectAudit + " ORDER BY audit_id DESC LIMIT @count", Map, ct, P("count", count));

    private static AuditEntry Map(DbDataReader r) => new(
        r.GetLong("audit_id"),
        r.GetText("table_name"),
        r.GetInt("record_id"),
        r.GetText("operation"),
        r.GetTimestamp("changed_at"),
        r.GetNullableText("changed_by_login"),
        r.GetNullableText("changes"));
}
