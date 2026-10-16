using System.Text;

namespace LibraryApp.Data;

public static class DbNames
{
    public static string ToDbName(Enum value)
    {
        var name = value.ToString();
        var sb = new StringBuilder(name.Length + 4);

        for (var i = 0; i < name.Length; i++)
        {
            var ch = name[i];
            if (char.IsUpper(ch) && i > 0)
            {
                sb.Append('_');
            }
            sb.Append(char.ToLowerInvariant(ch));
        }

        return sb.ToString();
    }

    public static TEnum FromDbName<TEnum>(string value) where TEnum : struct, Enum
    {
        var pascal = string.Concat(
            value.Split('_', StringSplitOptions.RemoveEmptyEntries)
                 .Select(part => char.ToUpperInvariant(part[0]) + part[1..]));

        return Enum.Parse<TEnum>(pascal, ignoreCase: true);
    }
}
