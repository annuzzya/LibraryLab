using System.Data.Common;
using LibraryApp.Domain;

namespace LibraryApp.Data;

public static class DbErrorTranslator
{
    public static LibraryException Translate(DbException ex)
    {
        var state = ex.SqlState;
        var message = CleanMessage(ex.Message, state);

        var kind = state switch
        {
            "P0001" or "22023" or "23514" => LibraryErrorKind.BusinessRule,
            "P0002" => LibraryErrorKind.NotFound,
            "23505" or "23P01" => LibraryErrorKind.Conflict,
            "28000" => LibraryErrorKind.Unauthorized,
            _ => LibraryErrorKind.Database
        };

        return new LibraryException(kind, message, state, ex);
    }

    private static string CleanMessage(string message, string? state)
    {
        if (state is not null && message.StartsWith(state + ":", StringComparison.Ordinal))
        {
            return message[(state.Length + 1)..].Trim();
        }

        return message;
    }
}
