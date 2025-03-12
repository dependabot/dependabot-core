using System.Text.RegularExpressions;

using Xunit;

using static NuGetUpdater.Core.Utilities.EOLHandling;

namespace NuGetUpdater.Core.Test.Utilities
{
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
    }
}
