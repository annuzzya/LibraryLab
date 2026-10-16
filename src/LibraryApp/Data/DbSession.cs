using System.Data.Common;

namespace LibraryApp.Data;

public sealed class DbSession
{
    public DbSession(DbConnection connection, DbTransaction transaction)
    {
        Connection = connection;
        Transaction = transaction;
    }

    public DbConnection Connection { get; }

    public DbTransaction Transaction { get; }

    public DbCommand CreateCommand(string sql, IEnumerable<DbParam> parameters)
    {
        var command = Connection.CreateCommand();
        command.Transaction = Transaction;
        command.CommandText = sql;

        foreach (var p in parameters)
        {
            var parameter = command.CreateParameter();
            parameter.ParameterName = p.Name;

            switch (p.Value)
            {
                case null:
                    parameter.Value = DBNull.Value;
                    break;
                case DateOnly date:
                    parameter.DbType = System.Data.DbType.Date;
                    parameter.Value = date.ToDateTime(TimeOnly.MinValue);
                    break;
                case Enum e:
                    parameter.Value = DbNames.ToDbName(e);
                    break;
                default:
                    parameter.Value = p.Value;
                    break;
            }

            command.Parameters.Add(parameter);
        }

        return command;
    }
}

public readonly record struct DbParam(string Name, object? Value);
