using System.Data.Common;
using LibraryApp.Data;
using LibraryApp.Domain;

namespace LibraryApp.Repositories;

public sealed class BookRepository : RepositoryBase, IBookRepository
{
    private const string SelectBooks =
        "SELECT book_id, isbn, title, publisher, publish_year, language, pages, description, authors, genres, " +
        "total_copies, available_copies, avg_rating, updated_at, updated_by_login FROM v_books_catalog";

    private const string SelectCopies =
        "SELECT copy_id, book_id, title, branch_id, branch_name, inventory_code, status, shelf, price FROM v_book_copies";

    public BookRepository(DbSession session) : base(session)
    {
    }

    public Task<Book?> GetByIdAsync(int id, CancellationToken ct = default) =>
        QuerySingleOrDefaultAsync(SelectBooks + " WHERE book_id = @id", MapBook, ct, P("id", id));

    public Task<IReadOnlyList<Book>> GetAllAsync(CancellationToken ct = default) =>
        QueryAsync(SelectBooks + " ORDER BY title", MapBook, ct);

    public Task<IReadOnlyList<BookSearchResult>> SearchAsync(string query, int limit = 10, CancellationToken ct = default) =>
        QueryAsync(
            "SELECT book_id, title, authors, publish_year, available_copies, relevance FROM fn_search_books(@query, @limit)",
            r => new BookSearchResult(
                r.GetInt("book_id"),
                r.GetText("title"),
                r.GetNullableText("authors") ?? string.Empty,
                r.GetNullableShort("publish_year"),
                r.GetInt("available_copies"),
                r.GetFloat("relevance")),
            ct,
            P("query", query),
            P("limit", limit));

    public Task<IReadOnlyList<BookCopy>> GetCopiesAsync(int bookId, CancellationToken ct = default) =>
        QueryAsync(SelectCopies + " WHERE book_id = @id ORDER BY branch_id, inventory_code", MapCopy, ct, P("id", bookId));

    public Task<BookCopy?> GetCopyByInventoryCodeAsync(string inventoryCode, CancellationToken ct = default) =>
        QuerySingleOrDefaultAsync(SelectCopies + " WHERE inventory_code = @code", MapCopy, ct, P("code", inventoryCode));

    public async Task<int> CreateAsync(NewBook book, CancellationToken ct = default)
    {
        var row = await CallAsync(
            "CALL sp_book_create(@isbn, @title, @publisher_id, @publish_year::smallint, @language, @pages, @description, @authors, @genres, NULL)",
            ct,
            P("isbn", book.Isbn),
            P("title", book.Title),
            P("publisher_id", book.PublisherId),
            P("publish_year", book.PublishYear),
            P("language", book.Language),
            P("pages", book.Pages),
            P("description", book.Description),
            P("authors", book.AuthorIds.ToArray()),
            P("genres", book.GenreIds.ToArray()));

        return ToInt(row[0]);
    }

    public Task UpdateAsync(int bookId, BookChanges changes, CancellationToken ct = default) =>
        ExecuteAsync(
            "CALL sp_book_update(@id, @title, @publisher_id, @publish_year::smallint, @pages, @description)",
            ct,
            P("id", bookId),
            P("title", changes.Title),
            P("publisher_id", changes.PublisherId),
            P("publish_year", changes.PublishYear),
            P("pages", changes.Pages),
            P("description", changes.Description));

    public Task SoftDeleteAsync(int bookId, CancellationToken ct = default) =>
        ExecuteAsync("CALL sp_book_soft_delete(@id)", ct, P("id", bookId));

    public async Task<int> AddCopyAsync(NewBookCopy copy, CancellationToken ct = default)
    {
        var row = await CallAsync(
            "CALL sp_copy_add(@book_id, @branch_id, @code, @shelf, @price, NULL)",
            ct,
            P("book_id", copy.BookId),
            P("branch_id", copy.BranchId),
            P("code", copy.InventoryCode),
            P("shelf", copy.Shelf),
            P("price", copy.Price));

        return ToInt(row[0]);
    }

    public Task WriteOffCopyAsync(int copyId, CancellationToken ct = default) =>
        ExecuteAsync("CALL sp_copy_write_off(@id)", ct, P("id", copyId));

    private static Book MapBook(DbDataReader r) => new(
        r.GetInt("book_id"),
        r.GetText("isbn"),
        r.GetText("title"),
        r.GetNullableText("publisher"),
        r.GetNullableShort("publish_year"),
        r.GetText("language"),
        r.GetNullableInt("pages"),
        r.GetNullableText("description"),
        r.GetText("authors"),
        r.GetText("genres"),
        r.GetInt("total_copies"),
        r.GetInt("available_copies"),
        r.GetNullableMoney("avg_rating"),
        r.GetTimestamp("updated_at"),
        r.GetNullableText("updated_by_login"));

    private static BookCopy MapCopy(DbDataReader r) => new(
        r.GetInt("copy_id"),
        r.GetInt("book_id"),
        r.GetText("title"),
        r.GetInt("branch_id"),
        r.GetText("branch_name"),
        r.GetText("inventory_code"),
        r.GetEnum<CopyStatus>("status"),
        r.GetNullableText("shelf"),
        r.GetNullableMoney("price"));
}
