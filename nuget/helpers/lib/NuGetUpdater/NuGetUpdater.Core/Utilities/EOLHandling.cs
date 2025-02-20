using System.Text.RegularExpressions;

namespace NuGetUpdater.Core.Utilities;

public static class EOLHandling
{
    /// <summary>
    /// Used to save (and then restore) which line endings are predominant in a file.
    /// </summary>
    public enum EOLType
    {
        /// <summary>
        /// Line feed - \n
        /// Typical on most systems.
        /// </summary>
        LF,
        /// <summary>
        /// Carriage return - \r
        /// Typical on older MacOS, unlikely (but possible) to come up here
        /// </summary>
        CR,
        /// <summary>
        /// Carriage return and line feed - \r\n.
        /// Typical on Windows
        /// </summary>
        CRLF
    };

    /// <summary>
    /// Analyze the input string and find the most common line ending type.
    /// </summary>
    /// <param name="content">The string to analyze</param>
    /// <returns>The most common type of line ending in the input string.</returns>
    public static EOLType GetPredominantEOL(this string content)
    {
        // Get stats on EOL characters/character sequences, if one predominates choose that for writing later.
        var lfcount = content.Count(c => c == '\n');
        var crcount = content.Count(c => c == '\r');
        var crlfcount = Regex.Matches(content, "\r\n").Count();

        // Since CRLF contains both a CR and a LF, subtract it from those counts
        lfcount -= crlfcount;
        crcount -= crlfcount;
        if (crcount > lfcount && crcount > crlfcount)
        {
            return EOLType.CR;
        }
        else if (crlfcount > lfcount)
        {
            return EOLType.CRLF;
        }
        else
        {
            return EOLType.LF;
        }
    }

    /// <summary>
    /// Given a line ending, modify the input string to uniformly use that line ending.
    /// </summary>
    /// <param name="content">The input string, which may have any combination of line endings.</param>
    /// <param name="desiredEOL">The line ending type to use across the result.</param>
    /// <returns>The string with any line endings swapped to the desired type.</returns>
    /// <exception cref="ArgumentOutOfRangeException">If EOLType is an unexpected value.</exception>
    public static string SetEOL(this string content, EOLType desiredEOL)
    {
        switch (desiredEOL)
        {
            case EOLType.LF:
                return Regex.Replace(content, "(\r\n|\r)", "\n");
            case EOLType.CR:
                return Regex.Replace(content, "(\r\n|\n)", "\r");
            case EOLType.CRLF:
                return Regex.Replace(content, "(\r\n|\r|\n)", "\r\n");
        }
        throw new ArgumentOutOfRangeException(nameof(desiredEOL));
    }
}
