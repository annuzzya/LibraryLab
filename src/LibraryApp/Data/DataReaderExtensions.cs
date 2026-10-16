using System.Data.Common;

namespace LibraryApp.Data;

public static class DataReaderExtensions
{
    public static int GetInt(this DbDataReader r, string column) =>
        Convert.ToInt32(r.GetValue(r.GetOrdinal(column)));

    public static long GetLong(this DbDataReader r, string column) =>
        Convert.ToInt64(r.GetValue(r.GetOrdinal(column)));

    public static int? GetNullableInt(this DbDataReader r, string column)
    {
        var i = r.GetOrdinal(column);
        return r.IsDBNull(i) ? null : Convert.ToInt32(r.GetValue(i));
    }

    public static short? GetNullableShort(this DbDataReader r, string column)
    {
        var i = r.GetOrdinal(column);
        return r.IsDBNull(i) ? null : Convert.ToInt16(r.GetValue(i));
    }

    public static string GetText(this DbDataReader r, string column) =>
        r.GetString(r.GetOrdinal(column));

    public static string? GetNullableText(this DbDataReader r, string column)
    {
        var i = r.GetOrdinal(column);
        return r.IsDBNull(i) ? null : Convert.ToString(r.GetValue(i));
    }

    public static decimal GetMoney(this DbDataReader r, string column) =>
        Convert.ToDecimal(r.GetValue(r.GetOrdinal(column)));

    public static decimal? GetNullableMoney(this DbDataReader r, string column)
    {
        var i = r.GetOrdinal(column);
        return r.IsDBNull(i) ? null : Convert.ToDecimal(r.GetValue(i));
    }

    public static float GetFloat(this DbDataReader r, string column) =>
        Convert.ToSingle(r.GetValue(r.GetOrdinal(column)));

    public static DateTime GetTimestamp(this DbDataReader r, string column) =>
        r.GetDateTime(r.GetOrdinal(column));

    public static DateTime? GetNullableTimestamp(this DbDataReader r, string column)
    {
        var i = r.GetOrdinal(column);
        return r.IsDBNull(i) ? null : r.GetDateTime(i);
    }

    public static DateOnly GetDate(this DbDataReader r, string column) =>
        DateOnly.FromDateTime(r.GetDateTime(r.GetOrdinal(column)));

    public static DateOnly? GetNullableDate(this DbDataReader r, string column)
    {
        var i = r.GetOrdinal(column);
        return r.IsDBNull(i) ? null : DateOnly.FromDateTime(r.GetDateTime(i));
    }

    public static TEnum GetEnum<TEnum>(this DbDataReader r, string column) where TEnum : struct, Enum =>
        DbNames.FromDbName<TEnum>(r.GetString(r.GetOrdinal(column)));
}
