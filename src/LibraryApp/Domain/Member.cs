namespace LibraryApp.Domain;

public sealed record Member(
    int Id,
    string CardNumber,
    string FirstName,
    string LastName,
    DateOnly? BirthDate,
    string Email,
    string? Phone,
    string? Address,
    DateTime RegisteredAt,
    string? PlanName,
    DateOnly? MembershipUntil,
    int ActiveLoans,
    decimal Debt,
    DateTime UpdatedAt,
    string? UpdatedBy)
{
    public string FullName => $"{FirstName} {LastName}";
}

public sealed record NewMember(
    string FirstName,
    string LastName,
    string Email,
    string? Phone,
    DateOnly? BirthDate,
    string? Address);

public sealed record MemberChanges(
    string FirstName,
    string LastName,
    string Email,
    string? Phone,
    string? Address);

public sealed record ArchivedMember(
    int Id,
    string CardNumber,
    string FullName,
    string Email,
    DateTime DeletedAt,
    string? DeletedBy);

public sealed record MembershipReceipt(int MembershipId, DateOnly ValidUntil);
