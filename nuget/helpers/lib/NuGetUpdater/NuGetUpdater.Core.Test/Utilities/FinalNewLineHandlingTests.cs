using static NuGetUpdater.Core.Utilities.EOLHandling;
using static NuGetUpdater.Core.Utilities.FinalNewLineHandling;

using Xunit;

namespace NuGetUpdater.Core.Test.Utilities;

public class FinalNewLineHandlingTests
{
    [Theory]
    [InlineData("line1\nline2\n", true)]
    [InlineData("line1\rline2\r", true)]
    [InlineData("line1\r\nline2\r\n", true)]
    [InlineData("line1\nline2", false)]
    [InlineData("line1\rline2", false)]
    [InlineData("line1\r\nline2", false)]
    [InlineData("", false)]
    public void HasFinalNewLineTests(string content, bool expected)
    {
        var actual = content.HasFinalNewLine();
        Assert.Equal(expected, actual);
    }

    [Theory]
    [InlineData("line1\nline2", true, EOLType.LF, "line1\nline2\n")]
    [InlineData("line1\rline2", true, EOLType.CR, "line1\rline2\r")]
    [InlineData("line1\r\nline2", true, EOLType.CRLF, "line1\r\nline2\r\n")]
    [InlineData("line1\nline2\n", false, EOLType.LF, "line1\nline2")]
    [InlineData("line1\rline2\r", false, EOLType.CR, "line1\rline2")]
    [InlineData("line1\r\nline2\r\n", false, EOLType.CRLF, "line1\r\nline2")]
    [InlineData("\n", false, EOLType.LF, "")]
    [InlineData("\r", false, EOLType.CR, "")]
    [InlineData("\r\n", false, EOLType.CRLF, "")]
    [InlineData("\n", true, EOLType.LF, "\n")]
    [InlineData("\r", true, EOLType.CR, "\r")]
    [InlineData("\r\n", true, EOLType.CRLF, "\r\n")]
    [InlineData("", false, EOLType.LF, "")]
    [InlineData("", false, EOLType.CR, "")]
    [InlineData("", false, EOLType.CRLF, "")]
    [InlineData("", true, EOLType.LF, "\n")]
    [InlineData("", true, EOLType.CR, "\r")]
    [InlineData("", true, EOLType.CRLF, "\r\n")]
    public void SetFinalNewLineTests(string content, bool setFinalNewLine, EOLType desiredEOL, string expected)
    {
        var actual = content.SetFinalNewLine(setFinalNewLine, desiredEOL);
        Assert.Equal(expected, actual);
    }

    [Fact]
    public void SetFinalNewLineWithInvalidEol()
    {
        // Assemble
        var content = "line1\nline2";
        var setFinalNewLine = true;
        var desiredEOL = (EOLType)999; // Invalid EOLType

        // Act & Assert
        Assert.Throws<ArgumentOutOfRangeException>(() => content.SetFinalNewLine(setFinalNewLine, desiredEOL));
    }
}
