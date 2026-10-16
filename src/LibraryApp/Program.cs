using System.Text;
using LibraryApp.Data;
using LibraryApp.Domain;
using LibraryApp.Services;

Console.OutputEncoding = Encoding.UTF8;

var connectionString = args.FirstOrDefault()
    ?? Environment.GetEnvironmentVariable("LIBRARY_DB")
    ?? "Host=localhost;Port=5432;Database=library_db;Username=postgres;Password=postgres;Search Path=library,public";

const int LibrarianId = 2;

var uowFactory = new UnitOfWorkFactory(new NpgsqlConnectionFactory(connectionString));
var library = new LibraryService(uowFactory);

await Step("1. Пошук книг у каталозі (fn_search_books)", async () =>
{
    await using var uow = await uowFactory.BeginAsync(LibrarianId);
    foreach (var query in new[] { "Жадан", "Design patern", "місто" })
    {
        Console.WriteLine($"  Запит: \"{query}\"");
        foreach (var book in await uow.Books.SearchAsync(query, 5))
        {
            Console.WriteLine($"    #{book.BookId,-3} {book.Title,-28} {book.Authors,-30} доступно: {book.AvailableCopies}");
        }
    }
});

Member? reader = null;

await Step("2. Реєстрація читача + купівля абонемента в одній транзакції", async () =>
{
    var suffix = DateTime.Now.ToString("HHmmss");
    reader = await library.RegisterReaderAsync(
        LibrarianId,
        new NewMember("Оксана", "Демченко", $"oksana.demchenko{suffix}@gmail.com", "+380671234567", new DateOnly(2002, 3, 18), "м. Київ, вул. Хорива, 4"),
        planId: 2,
        months: 6,
        PaymentMethod.Card);

    PrintMember(reader);
});

IReadOnlyList<LoanReceipt> receipts = Array.Empty<LoanReceipt>();

await Step("3. Видача двох книг (позики + зміна статусу примірників тригером)", async () =>
{
    receipts = await library.IssueBooksAsync(LibrarianId, reader!.Id, new[] { "INV-1-005-2", "INV-1-012-1" });
    foreach (var r in receipts)
    {
        Console.WriteLine($"  Позика #{r.LoanId}: примірник {r.CopyId}, повернути до {r.DueDate:dd.MM.yyyy}");
    }

    await using var uow = await uowFactory.BeginAsync(LibrarianId);
    foreach (var copy in await uow.Books.GetCopiesAsync(5))
    {
        Console.WriteLine($"    {copy.InventoryCode,-13} {copy.BranchName,-24} {copy.Status}");
    }
});

await Step("4. Атомарність: друга книга недоступна -> відкат усієї операції", async () =>
{
    try
    {
        await library.IssueBooksAsync(LibrarianId, reader!.Id, new[] { "INV-1-004-1", "INV-1-005-2" });
    }
    catch (LibraryException ex)
    {
        Console.WriteLine($"  Помилка ({ex.Kind}): {ex.Message}");
    }

    await using var uow = await uowFactory.BeginAsync(LibrarianId);
    var copy = await uow.Books.GetCopyByInventoryCodeAsync("INV-1-004-1");
    Console.WriteLine($"  Статус INV-1-004-1 після відкату: {copy!.Status}");
});

await Step("5. Продовження позики", async () =>
{
    var newDue = await library.ExtendLoanAsync(LibrarianId, receipts[0].LoanId, 7);
    Console.WriteLine($"  Позику #{receipts[0].LoanId} продовжено до {newDue:dd.MM.yyyy}");
});

await Step("6. Прострочені позики (v_overdue_loans)", async () =>
{
    await using var uow = await uowFactory.BeginAsync(LibrarianId);
    var marked = await uow.Loans.MarkOverdueAsync();
    foreach (var loan in await uow.Loans.GetOverdueAsync())
    {
        Console.WriteLine($"  #{loan.Id,-3} {loan.MemberName,-20} {loan.Title,-22} прострочено {loan.DaysOverdue,3} дн., штраф ~ {loan.FineEstimate,7:N2} грн");
    }
    await uow.CommitAsync();
    Console.WriteLine($"  Оновлено статусів: {marked}");
});

await Step("7. Повернення простроченої книги зі сплатою штрафу", async () =>
{
    int loanId;
    await using (var uow = await uowFactory.BeginAsync(LibrarianId))
    {
        var overdue = await uow.Loans.GetOverdueAsync();
        if (overdue.Count == 0)
        {
            Console.WriteLine("  Прострочених позик немає");
            return;
        }
        loanId = overdue[0].Id;
    }

    var result = await library.ReturnBookAsync(LibrarianId, loanId, PaymentMethod.Cash);
    Console.WriteLine($"  Позику #{loanId} закрито. Штраф: {result.Return.FineAmount:N2} грн, платіж #{result.PaymentId?.ToString() ?? "-"}");
});

await Step("8. Повернення вчасно + картка читача", async () =>
{
    var result = await library.ReturnBookAsync(LibrarianId, receipts[1].LoanId, null);
    Console.WriteLine($"  Позику #{receipts[1].LoanId} повернено, штраф: {(result.Return.HasFine ? result.Return.FineAmount.ToString("N2") : "немає")}");

    var card = await library.GetMemberCardAsync(LibrarianId, reader!.Id);
    PrintMember(card.Member);
    foreach (var loan in card.ActiveLoans)
    {
        Console.WriteLine($"    на руках: {loan.Title} (до {loan.DueDate:dd.MM.yyyy}, продовжень: {loan.Extensions})");
    }
});

await Step("9. Soft delete: читач з книгою на руках не може бути видалений", async () =>
{
    try
    {
        await library.RemoveReaderAsync(LibrarianId, reader!.Id);
    }
    catch (LibraryException ex)
    {
        Console.WriteLine($"  Помилка ({ex.Kind}): {ex.Message}");
    }

    await library.ReturnBookAsync(LibrarianId, receipts[0].LoanId, null);
    await library.RemoveReaderAsync(LibrarianId, reader!.Id);

    await using var uow = await uowFactory.BeginAsync(LibrarianId);
    var active = await uow.Members.GetByIdAsync(reader!.Id);
    Console.WriteLine($"  У v_members: {(active is null ? "відсутній" : "присутній")}");
    foreach (var a in (await uow.Members.GetArchivedAsync()).Take(3))
    {
        Console.WriteLine($"  Архів: {a.CardNumber} {a.FullName}, видалено {a.DeletedAt.ToLocalTime():dd.MM.yyyy HH:mm} ({a.DeletedBy})");
    }
});

await Step("10. Відновлення читача та журнал змін", async () =>
{
    await library.RestoreReaderAsync(LibrarianId, reader!.Id);

    await using var uow = await uowFactory.BeginAsync(LibrarianId);
    foreach (var entry in await uow.Audit.GetForRecordAsync("members", reader!.Id))
    {
        Console.WriteLine($"  {entry.ChangedAt.ToLocalTime():HH:mm:ss} {entry.Operation,-6} by {entry.ChangedBy ?? "system",-9} {Shorten(entry.Changes, 90)}");
    }
});

await Step("11. Каталогізатор: нова книга + примірники, потім списання (soft delete)", async () =>
{
    const int CatalogerId = 5;
    int bookId;

    await using (var uow = await uowFactory.BeginAsync(CatalogerId))
    {
        bookId = await uow.Books.CreateAsync(new NewBook(
            "978-617-679-819-2",
            "Амадока",
            PublisherId: 1,
            PublishYear: 2020,
            Language: "uk",
            Pages: 832,
            Description: "Роман про пам'ять, ідентичність та втрачене минуле",
            AuthorIds: new[] { 9 },
            GenreIds: new[] { 4 }));

        await uow.Books.AddCopyAsync(new NewBookCopy(bookId, 1, $"INV-1-{bookId:000}-1", "G-1", 380m));
        await uow.Books.AddCopyAsync(new NewBookCopy(bookId, 2, $"INV-2-{bookId:000}-1", "G-4", 380m));
        await uow.CommitAsync();
    }

    await using (var uow = await uowFactory.BeginAsync(CatalogerId))
    {
        var book = await uow.Books.GetByIdAsync(bookId);
        Console.WriteLine($"  #{book!.Id} {book.Title} ({book.Authors}; {book.Genres}), примірників: {book.TotalCopies}, доступно: {book.AvailableCopies}, додав: {book.UpdatedBy}");

        await uow.Books.SoftDeleteAsync(bookId);
        var afterDelete = await uow.Books.GetByIdAsync(bookId);
        Console.WriteLine($"  Після списання у каталозі: {(afterDelete is null ? "відсутня" : "присутня")}");
        await uow.CommitAsync();
    }
});

static async Task Step(string title, Func<Task> action)
{
    Console.WriteLine();
    Console.WriteLine(title);
    Console.WriteLine(new string('-', title.Length));
    try
    {
        await action();
    }
    catch (LibraryException ex)
    {
        Console.WriteLine($"  Помилка ({ex.Kind}): {ex.Message}");
    }
}

static void PrintMember(Member m)
{
    Console.WriteLine($"  {m.CardNumber} {m.FullName} <{m.Email}>");
    Console.WriteLine($"  Тариф: {m.PlanName ?? "немає"} до {m.MembershipUntil:dd.MM.yyyy}, книг на руках: {m.ActiveLoans}, борг: {m.Debt:N2} грн, змінив: {m.UpdatedBy}");
}

static string Shorten(string? text, int max) =>
    text is null ? string.Empty : text.Length <= max ? text : text[..max] + "...";
