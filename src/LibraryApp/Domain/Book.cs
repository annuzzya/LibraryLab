namespace LibraryApp.Domain;

public sealed record Book(
    int Id,
    string Isbn,
    string Title,
    string? Publisher,
    short? PublishYear,
    string Language,
    int? Pages,
    string? Description,
    string Authors,
    string Genres,
    int TotalCopies,
    int AvailableCopies,
    decimal? AverageRating,
    DateTime UpdatedAt,
    string? UpdatedBy);

public sealed record NewBook(
    string Isbn,
    string Title,
    int? PublisherId,
    short? PublishYear,
    string Language,
    int? Pages,
    string? Description,
    IReadOnlyList<int> AuthorIds,
    IReadOnlyList<int> GenreIds);

public sealed record BookChanges(
    string Title,
    int? PublisherId,
    short? PublishYear,
    int? Pages,
    string? Description);

public sealed record BookSearchResult(
    int BookId,
    string Title,
    string Authors,
    short? PublishYear,
    int AvailableCopies,
    float Relevance);

public enum CopyStatus
{
    Available,
    OnLoan,
    Reserved,
    InRepair,
    Lost,
    WrittenOff
}

public sealed record BookCopy(
    int Id,
    int BookId,
    string Title,
    int BranchId,
    string BranchName,
    string InventoryCode,
    CopyStatus Status,
    string? Shelf,
    decimal? Price);

public sealed record NewBookCopy(
    int BookId,
    int BranchId,
    string InventoryCode,
    string? Shelf,
    decimal? Price);
