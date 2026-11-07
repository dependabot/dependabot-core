using static NuGetUpdater.Core.Utilities.EOLHandling;

namespace NuGetUpdater.Core.Utilities;

public static class FinalNewLineHandling
{
    /// <summary>
    /// Determines if a string has a trailing newline character (either '\n' or '\r').
    /// </summary>
    /// <param name="content">The string to check.</param>
    /// <returns>A boolean indicating whether the string has a trailing newline character.</returns>
    public static bool HasFinalNewLine(this string content)
    {
        if (string.IsNullOrEmpty(content))
        {
            return false;
        }

        return content.EndsWith('\n') || content.EndsWith('\r');
    }

    /// <summary>
    /// Ensures a string either ends with the given line ending, or has any trailing line endings removed.
    /// </summary>
    /// <param name="content">The target string.</param>
    /// <param name="setFinalNewLine">True to append <paramref name="desiredEOL"/> if missing; false to strip trailing newlines.</param>
    /// <param name="desiredEOL">The line ending to append when <paramref name="setFinalNewLine"/> is true.</param>
    /// <returns>The content with its final newline state set as requested.</returns>
    public static string SetFinalNewLine(this string content, bool setFinalNewLine, EOLType desiredEOL)
    {
        if (content.HasFinalNewLine())
        {
            return setFinalNewLine ? content : content.TrimEnd('\r', '\n');
        }

        if (!setFinalNewLine)
        {
            return content;
        }

        var newLine = desiredEOL switch
        {
            EOLType.LF => "\n",
            EOLType.CR => "\r",
            EOLType.CRLF => "\r\n",
            _ => throw new ArgumentOutOfRangeException(nameof(desiredEOL)),
        };

        return content + newLine;
    }
}
