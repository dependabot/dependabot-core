using System.Collections;
using System.Collections.Immutable;
using System.Reflection;
using System.Text;

using Xunit;

namespace NuGetUpdater.Core.Test.Utilities;

/// <summary>
/// Assert style type to deal with the lack of features in xUnit's Assert type
/// </summary>
public static class AssertEx
{
    public static void Equal<T>(
        ImmutableArray<T>? expected,
        ImmutableArray<T>? actual,
        IEqualityComparer<T>? comparer = null,
        string? message = null)
    {
        if (actual is null || actual.Value.IsDefault)
        {
            Assert.True(expected is null || expected.Value.IsDefault, message);
        }
        else
        {
            Equal(expected, (IEnumerable<T>)actual.Value, comparer, message);
        }
    }

    public static void Equal<T>(
        ImmutableArray<T> expected,
        ImmutableArray<T> actual,
        IEqualityComparer<T>? comparer = null,
        string? message = null)
    {
        if (actual.IsDefault)
        {
            Assert.True(expected.IsDefault, message);
        }
        else
        {
            Equal(expected, (IEnumerable<T>)actual, comparer, message);
        }
    }

    public static void Equal<T>(
        ImmutableArray<T>? expected,
        IEnumerable<T>? actual,
        IEqualityComparer<T>? comparer = null,
        string? message = null)
    {
        if (expected is null || expected.Value.IsDefault)
        {
            Assert.True(actual is null, message);
        }
        else
        {
            Equal((IEnumerable<T>?)expected, actual, comparer, message);
        }
    }

    public static void Equal<T>(
        IEnumerable<T>? expected,
        ImmutableArray<T>? actual,
        IEqualityComparer<T>? comparer = null,
        string? message = null)
    {
        if (actual is null || actual.Value.IsDefault)
        {
            Assert.True(expected is null, message);
        }
        else
        {
            Equal(expected, (IEnumerable<T>)actual, comparer, message);
        }
    }

    public static void Equal<T>(
        IEnumerable<T>? expected,
        IEnumerable<T>? actual,
        IEqualityComparer<T>? comparer = null,
        string? message = null)
    {
        if (expected == null)
        {
            Assert.True(actual is null, message);
            return;
        }
        else
        {
            Assert.True(actual is not null, message);
        }

        if (SequenceEqual(expected, actual, comparer))
        {
            return;
        }

        Assert.Fail(GetAssertMessage(expected, actual, comparer, message));
    }

    private static bool SequenceEqual<T>(
        IEnumerable<T> expected,
        IEnumerable<T> actual,
        IEqualityComparer<T>? comparer = null)
    {
        if (ReferenceEquals(expected, actual))
        {
            return true;
        }

        var enumerator1 = expected.GetEnumerator();
        var enumerator2 = actual.GetEnumerator();

        while (true)
        {
            var hasNext1 = enumerator1.MoveNext();
            var hasNext2 = enumerator2.MoveNext();

            if (hasNext1 != hasNext2)
            {
                return false;
            }

            if (!hasNext1)
            {
                break;
            }

            var value1 = enumerator1.Current;
            var value2 = enumerator2.Current;

            var areEqual = comparer != null
                ? comparer.Equals(value1, value2)
                : AssertEqualityComparer<T>.Equals(value1, value2);
            if (!areEqual)
            {
                return false;
            }
        }

        return true;
    }

    public static string GetAssertMessage<T>(
        IEnumerable<T> expected,
        IEnumerable<T> actual,
        IEqualityComparer<T>? comparer = null,
        string? prefix = null)
    {
        Func<T, string> itemInspector = typeof(T) == typeof(byte)
            ? b => $"0x{b:X2}"
            : new Func<T, string>(obj => obj?.ToString() ?? "<null>");

        var itemSeparator = typeof(T) == typeof(byte)
            ? ", "
            : "," + Environment.NewLine;

        var expectedString = string.Join(itemSeparator, expected.Take(10).Select(itemInspector));
        var actualString = string.Join(itemSeparator, actual.Select(itemInspector));

        var message = new StringBuilder();

        if (!string.IsNullOrEmpty(prefix))
        {
            message.AppendLine(prefix);
            message.AppendLine();
        }

        message.AppendLine("Expected:");
        message.AppendLine(expectedString);
        if (expected.Count() > 10)
        {
            message.AppendLine("... truncated ...");
        }

        message.AppendLine("Actual:");
        message.AppendLine(actualString);
        message.AppendLine("Differences:");
        message.AppendLine(DiffUtil.DiffReport(expected, actual, itemSeparator, comparer, itemInspector));

        return message.ToString();
    }

    private class AssertEqualityComparer<T> : IEqualityComparer<T>
    {
        public static readonly IEqualityComparer<T> Instance = new AssertEqualityComparer<T>();

        private static bool CanBeNull()
        {
            var type = typeof(T);
            return !type.GetTypeInfo().IsValueType ||
                (type.GetTypeInfo().IsGenericType && type.GetGenericTypeDefinition() == typeof(Nullable<>));
        }

        public static bool IsNull(T @object)
        {
            if (!CanBeNull())
            {
                return false;
            }

            return object.Equals(@object, default(T));
        }

        public static bool Equals(T left, T right)
        {
            return Instance.Equals(left, right);
        }

        bool IEqualityComparer<T>.Equals(T? x, T? y)
        {
            if (CanBeNull())
            {
                if (object.Equals(x, default(T)))
                {
                    return object.Equals(y, default(T));
                }

                if (object.Equals(y, default(T)))
                {
                    return false;
                }
            }

            if (x is IEquatable<T> equatable)
            {
                return equatable.Equals(y);
            }

            if (x is IComparable<T> comparableT)
            {
                return comparableT.CompareTo(y) == 0;
            }

            if (x is IComparable comparable)
            {
                return comparable.CompareTo(y) == 0;
            }

            if (x is IEnumerable enumerableX && y is IEnumerable enumerableY)
            {
                var enumeratorX = enumerableX.GetEnumerator();
                var enumeratorY = enumerableY.GetEnumerator();

                while (true)
                {
                    bool hasNextX = enumeratorX.MoveNext();
                    bool hasNextY = enumeratorY.MoveNext();

                    if (!hasNextX || !hasNextY)
                    {
                        return hasNextX == hasNextY;
                    }

                    if (!Equals(enumeratorX.Current, enumeratorY.Current))
                    {
                        return false;
                    }
                }
            }

            return object.Equals(x, y);
        }

        int IEqualityComparer<T>.GetHashCode(T obj)
        {
            throw new NotImplementedException();
        }
    }
}
