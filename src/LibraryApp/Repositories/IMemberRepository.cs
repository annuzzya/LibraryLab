using LibraryApp.Domain;

namespace LibraryApp.Repositories;

public interface IMemberRepository : IReadRepository<Member, int>
{
    Task<Member?> GetByCardNumberAsync(string cardNumber, CancellationToken ct = default);

    Task<IReadOnlyList<ArchivedMember>> GetArchivedAsync(CancellationToken ct = default);

    Task<(int Id, string CardNumber)> RegisterAsync(NewMember member, CancellationToken ct = default);

    Task UpdateAsync(int memberId, MemberChanges changes, CancellationToken ct = default);

    Task SoftDeleteAsync(int memberId, CancellationToken ct = default);

    Task RestoreAsync(int memberId, CancellationToken ct = default);

    Task<MembershipReceipt> PurchaseMembershipAsync(int memberId, int planId, int months, PaymentMethod method, CancellationToken ct = default);
}
