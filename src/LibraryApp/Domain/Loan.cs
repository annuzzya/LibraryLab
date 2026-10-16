namespace LibraryApp.Domain;

public enum LoanStatus
{
    Active,
    Returned,
    Overdue,
    Lost
}

public sealed record Loan(
    int Id,
    int MemberId,
    string CardNumber,
    string MemberName,
    int CopyId,
    string InventoryCode,
    int BookId,
    string Title,
    string BranchName,
    DateTime LoanDate,
    DateOnly DueDate,
    DateTime? ReturnDate,
    int Extensions,
    LoanStatus Status,
    int DaysOverdue,
    decimal FineEstimate)
{
    public bool IsOpen => ReturnDate is null;
}

public sealed record LoanReceipt(int LoanId, int CopyId, DateOnly DueDate);

public sealed record ReturnResult(int LoanId, int? FineId, decimal FineAmount)
{
    public bool HasFine => FineId is not null;
}
