using NuGetUpdater.Core.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Utilities;

public class BOMHandlingTests
{
    [Theory]
    [MemberData(nameof(HasBOMTestData))]
    public void HasBOM(byte[] content, bool expectedHasBOM)
    {
        var actualHasBOM = content.HasBOM();
        Assert.Equal(expectedHasBOM, actualHasBOM);
    }

    [Theory]
    [MemberData(nameof(SetBOMTestData))]
    public void SetBOM(string content, bool setBOM, byte[] expectedBytes)
    {
        var actualBytes = content.SetBOM(setBOM);
        AssertEx.Equal(expectedBytes, actualBytes);
    }

    public static IEnumerable<object[]> HasBOMTestData()
    {
        yield return
        [
            // content
            new byte[] { 0xEF, 0xBB, 0xBF, (byte)'A' },
            // expectedHasBOM
            true
        ];

        yield return
        [
            // content
            new byte[] { (byte)'A' },
            // expectedHasBOM
            false
        ];
    }

    public static IEnumerable<object[]> SetBOMTestData()
    {
        yield return
        [
            // content
            "A",
            // setBOM
            true,
            // expectedBytes
            new byte[] { 0xEF, 0xBB, 0xBF, (byte)'A' }
        ];

        yield return
        [
            // content
            "A",
            // setBOM
            false,
            // expectedBytes
            new byte[] { (byte)'A' }
        ];
    }
}
