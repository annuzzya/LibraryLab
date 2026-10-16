namespace LibraryApp.Domain;

public enum LibraryErrorKind
{
    BusinessRule,
    NotFound,
    Conflict,
    Unauthorized,
    Database
}

public sealed class LibraryException : Exception
{
    public LibraryException(LibraryErrorKind kind, string message, string? sqlState = null, Exception? inner = null)
        : base(message, inner)
    {
        Kind = kind;
        SqlState = sqlState;
    }

    public LibraryErrorKind Kind { get; }

    public string? SqlState { get; }
}
