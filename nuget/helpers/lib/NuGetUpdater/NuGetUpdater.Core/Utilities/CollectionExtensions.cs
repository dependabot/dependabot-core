using Newtonsoft.Json.Linq;

namespace NuGetUpdater.Core.Utilities;

public static class CollectionExtensions
{
    public static TValue GetOrAdd<TKey, TValue>(this Dictionary<TKey, TValue> dictionary, TKey key, Func<TValue> valueFactory) where TKey : notnull
    {
        if (!dictionary.TryGetValue(key, out var value))
        {
            value = valueFactory();
            dictionary[key] = value;
        }

        return value;
    }
}
