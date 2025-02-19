namespace NuGetUpdater.Core.Test.Run;

public static class StringExtensions
{
    public static string SetEOL(this string input, string EOL) => input.Replace("\r\n", EOL).Replace("\r", EOL).Replace("\n", EOL);
}
