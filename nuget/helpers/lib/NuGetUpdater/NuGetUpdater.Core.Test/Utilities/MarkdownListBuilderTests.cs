using NuGetUpdater.Core.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Utilities;

public class MarkdownListBuilderTests
{
    [Theory]
    [MemberData(nameof(ListCreationTestData))]
    public void ListCreation(object obj, string expected)
    {
        expected = expected.Replace("\r", "");
        var actual = MarkdownListBuilder.FromObject(obj).Replace("\r", "");
        Assert.Equal(expected, actual);
    }

    public static IEnumerable<object[]> ListCreationTestData()
    {
        yield return
        [
            new Dictionary<string, object>()
            {
                ["key1"] = "value1",
                ["key2"] = new[]
                {
                    new Dictionary<string, object>()
                    {
                        ["key11"] = "value11",
                        ["key12"] = "value12"
                    }
                }
            },
            """
            - key1: value1
            - key2:
              - - key11: value11
                - key12: value12
            """
        ];
    }
}
