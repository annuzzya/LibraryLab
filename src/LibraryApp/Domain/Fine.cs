namespace LibraryApp.Domain;

public enum FineStatus
{
    Unpaid,
    Paid,
    Waived
}

public enum PaymentMethod
{
    Cash,
    Card,
    Online
}

public sealed record Fine(
    int Id,
    int MemberId,
    string MemberName,
    int? LoanId,
    decimal Amount,
    string Reason,
    FineStatus Status,
    DateTime IssuedAt,
    DateTime? PaidAt);

public sealed record AuditEntry(
    long Id,
    string TableName,
    int RecordId,
    string Operation,
    DateTime ChangedAt,
    string? ChangedBy,
    string? Changes);
