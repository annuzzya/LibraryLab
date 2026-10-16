using System.Data.Common;

namespace LibraryApp.Data;

public interface IConnectionFactory
{
    DbConnection Create();
}
