using LibraryApp.Domain;

namespace LibraryApp.Repositories;

public interface IFineRepository : IReadRepository<Fine, int>
{
    Task<IReadOnlyList<Fine>> GetByMemberAsync(int memberId, bool onlyUnpaid = false, CancellationToken ct = default);

    Task<int> PayAsync(int fineId, PaymentMethod method, CancellationToken ct = default);

    Task WaiveAsync(int fineId, string comment, CancellationToken ct = default);
}
