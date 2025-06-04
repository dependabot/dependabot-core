using System.Text.RegularExpressions;

using Xunit;

using static NuGetUpdater.Core.Utilities.EOLHandling;

namespace NuGetUpdater.Core.Test.Utilities;

public class EOLHandlingTests
{
    [Theory]
    [InlineData(EOLType.LF, "\n")]
    [InlineData(EOLType.CR, "\r")]
    [InlineData(EOLType.CRLF, "\r\n")]
    public void ValidateEOLNormalizesFromLF(EOLType eolType, string literal)
    {
        var teststring = "this\ris\na\r\nstring\rwith\nmixed\r\nline\rendings\n.";
        var changed = teststring.SetEOL(eolType);
        var lineEndings = Regex.Split(changed, "\\S+");
        Assert.All(lineEndings, lineEnding => lineEnding.Equals(literal));
    }

    [Theory]
    [MemberData(nameof(GetPredominantEOLTestData))]
    public void GetPredominantEOL(string fileContent, EOLType expectedEOL)
    {
        var actualEOL = fileContent.GetPredominantEOL();
        Assert.Equal(expectedEOL, actualEOL);
    }

    [Theory]
    [MemberData(nameof(SetEOLTestData))]
    public void SetEOL(string currentFileContent, EOLType desiredEOL, string expectedFileContent)
    {
        var actualFileContent = currentFileContent.SetEOL(desiredEOL);
        Assert.Equal(expectedFileContent, actualFileContent);
    }

    public static IEnumerable<object[]> GetPredominantEOLTestData()
    {
        // purely CR
        yield return
        [
            // fileContent
            string.Concat(
            "line1\r",
            "line2\r",
            "line3\r"
        ),
        // expectedEOL
        EOLType.CR
        ];

        // purely LF
        yield return
        [
            // fileContent
            string.Concat(
            "line1\n",
            "line2\n",
            "line3\n"
        ),
        // expectedEOL
        EOLType.LF
        ];

        // purely CRLF
        yield return
        [
            // fileContent
            string.Concat(
            "line1\r\n",
            "line2\r\n",
            "line3\r\n"
        ),
        // expectedEOL
        EOLType.CRLF
        ];

        // mostly CR
        yield return
        [
            // fileContent
            string.Concat(
            "line1\r",
            "line2\n",
            "line3\r"
        ),
        // expectedEOL
        EOLType.CR
        ];

        // mostly LF
        yield return
        [
            // fileContent
            string.Concat(
            "line1\n",
            "line2\r",
            "line3\n"
        ),
        // expectedEOL
        EOLType.LF
        ];

        // mostly CRLF
        yield return
        [
            // fileContent
            string.Concat(
            "line1\r\n",
            "line2\n",
            "line3\r",
            "line4\r\n"
        ),
        // expectedEOL
        EOLType.CRLF
        ];
    }

    public static IEnumerable<object[]> SetEOLTestData()
    {
        // CR to CR
        yield return
        [
            // currentFileContent
            string.Concat(
            "line1\r",
            "line2\r",
            "line3\r"
        ),
        // desiredEOL
        EOLType.CR,
        // expectedFileContent
        string.Concat(
            "line1\r",
            "line2\r",
            "line3\r"
        )
        ];

        // LF to LF
        yield return
        [
            // currentFileContent
            string.Concat(
            "line1\n",
            "line2\n",
            "line3\n"
        ),
        // desiredEOL
        EOLType.LF,
        // expectedFileContent
        string.Concat(
            "line1\n",
            "line2\n",
            "line3\n"
        )
        ];

        // CRLF to CRLF
        yield return
        [
            // currentFileContent
            string.Concat(
            "line1\r\n",
            "line2\r\n",
            "line3\r\n"
        ),
        // desiredEOL
        EOLType.CRLF,
        // expectedFileContent
        string.Concat(
            "line1\r\n",
            "line2\r\n",
            "line3\r\n"
        )
        ];

        // mixed to CR
        yield return
        [
            // currentFileContent
            string.Concat(
            "line1\r",
            "line2\n",
            "line3\r\n"
        ),
        // desiredEOL
        EOLType.CR,
        // expectedFileContent
        string.Concat(
            "line1\r",
            "line2\r",
            "line3\r"
        )
        ];

        // mixed to LF
        yield return
        [
            // currentFileContent
            string.Concat(
            "line1\r",
            "line2\n",
            "line3\r\n"
        ),
        // desiredEOL
        EOLType.LF,
        // expectedFileContent
        string.Concat(
            "line1\n",
            "line2\n",
            "line3\n"
        )
        ];

        // mixed to CRLF
        yield return
        [
            // currentFileContent
            string.Concat(
            "line1\r",
            "line2\n",
            "line3\r\n"
        ),
        // desiredEOL
        EOLType.CRLF,
        // expectedFileContent
        string.Concat(
            "line1\r\n",
            "line2\r\n",
            "line3\r\n"
        )
        ];
    }
}
