using System.Data.Common;
using LibraryApp.Data;

namespace LibraryApp.Repositories;

public abstract class RepositoryBase
{
    private readonly DbSession _session;

    protected RepositoryBase(DbSession session)
    {
        _session = session;
    }

    protected static DbParam P(string name, object? value) => new(name, value);

    protected async Task<IReadOnlyList<T>> QueryAsync<T>(
        string sql,
        Func<DbDataReader, T> map,
        CancellationToken ct,
        params DbParam[] parameters)
    {
        try
        {
            await using var command = _session.CreateCommand(sql, parameters);
            await using var reader = await command.ExecuteReaderAsync(ct);

            var result = new List<T>();
            while (await reader.ReadAsync(ct))
            {
                result.Add(map(reader));
            }
            return result;
        }
        catch (DbException ex)
        {
            throw DbErrorTranslator.Translate(ex);
        }
    }

    protected async Task<T?> QuerySingleOrDefaultAsync<T>(
        string sql,
        Func<DbDataReader, T> map,
        CancellationToken ct,
        params DbParam[] parameters) where T : class
    {
        var rows = await QueryAsync(sql, map, ct, parameters);
        return rows.Count switch
        {
            0 => null,
            1 => rows[0],
            _ => throw new InvalidOperationException($"Query returned {rows.Count} rows, expected one")
        };
    }

    protected async Task<object?[]> CallAsync(string sql, CancellationToken ct, params DbParam[] parameters)
    {
        try
        {
            await using var command = _session.CreateCommand(sql, parameters);
            await using var reader = await command.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
            {
                return Array.Empty<object?>();
            }

            var values = new object?[reader.FieldCount];
            for (var i = 0; i < reader.FieldCount; i++)
            {
                values[i] = reader.IsDBNull(i) ? null : reader.GetValue(i);
            }
            return values;
        }
        catch (DbException ex)
        {
            throw DbErrorTranslator.Translate(ex);
        }
    }

    protected async Task ExecuteAsync(string sql, CancellationToken ct, params DbParam[] parameters)
    {
        try
        {
            await using var command = _session.CreateCommand(sql, parameters);
            await command.ExecuteNonQueryAsync(ct);
        }
        catch (DbException ex)
        {
            throw DbErrorTranslator.Translate(ex);
        }
    }

    protected static int ToInt(object? value) => Convert.ToInt32(value);

    protected static int? ToNullableInt(object? value) => value is null ? null : Convert.ToInt32(value);

    protected static decimal ToDecimal(object? value) => value is null ? 0m : Convert.ToDecimal(value);

    protected static DateOnly ToDate(object? value) => value switch
    {
        DateOnly d => d,
        DateTime dt => DateOnly.FromDateTime(dt),
        _ => throw new InvalidCastException($"Cannot convert {value?.GetType().Name ?? "null"} to DateOnly")
    };
}
