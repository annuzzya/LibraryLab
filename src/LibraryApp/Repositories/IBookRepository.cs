using LibraryApp.Domain;

namespace LibraryApp.Repositories;

public interface IBookRepository : IReadRepository<Book, int>
{
    Task<IReadOnlyList<BookSearchResult>> SearchAsync(string query, int limit = 10, CancellationToken ct = default);

    Task<IReadOnlyList<BookCopy>> GetCopiesAsync(int bookId, CancellationToken ct = default);

    Task<BookCopy?> GetCopyByInventoryCodeAsync(string inventoryCode, CancellationToken ct = default);

    Task<int> CreateAsync(NewBook book, CancellationToken ct = default);

    Task UpdateAsync(int bookId, BookChanges changes, CancellationToken ct = default);

    Task SoftDeleteAsync(int bookId, CancellationToken ct = default);

    Task<int> AddCopyAsync(NewBookCopy copy, CancellationToken ct = default);

    Task WriteOffCopyAsync(int copyId, CancellationToken ct = default);
}
