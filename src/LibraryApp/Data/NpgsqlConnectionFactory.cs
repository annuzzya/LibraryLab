using System.Data.Common;
using Npgsql;

namespace LibraryApp.Data;

public sealed class NpgsqlConnectionFactory : IConnectionFactory
{
    private readonly string _connectionString;

    public NpgsqlConnectionFactory(string connectionString)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new ArgumentException("Connection string is empty", nameof(connectionString));
        }

        _connectionString = connectionString;
    }

    public DbConnection Create() => new NpgsqlConnection(_connectionString);
}
