using System.Collections.Immutable;
using System.Text.RegularExpressions;

namespace NuGetUpdater.Core.Utilities;

internal class GitIgnoreParser
{
    private readonly ImmutableArray<GitIgnoreRule> _rules;

    private GitIgnoreParser(ImmutableArray<GitIgnoreRule> rules)
    {
        _rules = rules;
    }

    /// <summary>
    /// Collects all .gitignore files from the repo root up to and including the directory containing the file being tested.
    /// </summary>
    public static GitIgnoreParser FromRepoRoot(string repoRootPath)
    {
        var rules = new List<GitIgnoreRule>();
        CollectRulesFromDirectory(repoRootPath, repoRootPath, rules);
        return new GitIgnoreParser([.. rules]);
    }

    /// <summary>
    /// Determines if a path (relative to the repo root, using unix-style separators) is ignored by any .gitignore rule.
    /// </summary>
    public bool IsIgnored(string relativePath)
    {
        relativePath = relativePath.NormalizePathToUnix().TrimStart('/');

        // Process rules in order; later rules can override earlier ones (negation patterns)
        bool ignored = false;
        foreach (var rule in _rules)
        {
            if (rule.IsMatch(relativePath))
            {
                ignored = !rule.IsNegation;
            }
        }

        return ignored;
    }

    private static void CollectRulesFromDirectory(string repoRootPath, string currentDirectory, List<GitIgnoreRule> rules)
    {
        var gitignorePath = Path.Combine(currentDirectory, ".gitignore");
        if (File.Exists(gitignorePath))
        {
            var content = File.ReadAllText(gitignorePath);
            var directoryRelativeToRoot = Path.GetRelativePath(repoRootPath, currentDirectory).NormalizePathToUnix();
            var prefix = directoryRelativeToRoot == "." ? "" : directoryRelativeToRoot + "/";
            var parsed = ParseRules(content, prefix);
            rules.AddRange(parsed);
        }

        // Recurse into subdirectories
        foreach (var subDir in Directory.EnumerateDirectories(currentDirectory))
        {
            var dirName = Path.GetFileName(subDir);
            if (dirName == ".git")
            {
                continue;
            }

            CollectRulesFromDirectory(repoRootPath, subDir, rules);
        }
    }

    internal static ImmutableArray<GitIgnoreRule> ParseRules(string content, string pathPrefix)
    {
        var rules = new List<GitIgnoreRule>();
        foreach (var rawLine in content.Split('\n'))
        {
            var line = rawLine.TrimEnd('\r').TrimEnd();

            // skip empty lines and comments
            if (string.IsNullOrWhiteSpace(line) || line.StartsWith('#'))
            {
                continue;
            }

            bool isNegation = false;
            if (line.StartsWith('!'))
            {
                isNegation = true;
                line = line[1..];
            }

            // remove trailing spaces (unless escaped)
            line = line.TrimEnd();

            if (string.IsNullOrEmpty(line))
            {
                continue;
            }

            bool directoryOnly = line.EndsWith('/');
            if (directoryOnly)
            {
                line = line.TrimEnd('/');
            }

            // A leading slash means "rooted at the .gitignore location"
            bool hasLeadingSlash = line.StartsWith('/');
            if (hasLeadingSlash)
            {
                line = line[1..];
            }

            // If the pattern contains a slash (not at the end) or has a leading slash,
            // it's relative to the .gitignore location.
            // Otherwise it matches at any depth within the .gitignore's directory scope.
            bool isRooted = hasLeadingSlash || line.Contains('/');

            var regex = ConvertPatternToRegex(line, isRooted, directoryOnly, pathPrefix);

            rules.Add(new GitIgnoreRule(regex, isNegation, directoryOnly));
        }

        return [.. rules];
    }

    private static Regex ConvertPatternToRegex(string pattern, bool isRooted, bool directoryOnly, string pathPrefix)
    {
        // Convert gitignore glob pattern to regex
        var regexPattern = "^";

        if (isRooted)
        {
            // Rooted patterns are anchored at the .gitignore directory
            if (!string.IsNullOrEmpty(pathPrefix))
            {
                regexPattern += Regex.Escape(pathPrefix);
            }
        }
        else
        {
            // Unrooted patterns match at any depth within the .gitignore directory scope
            if (!string.IsNullOrEmpty(pathPrefix))
            {
                regexPattern += Regex.Escape(pathPrefix) + "(.*/)?";
            }
            else
            {
                regexPattern += "(.*/)?";
            }
        }

        for (int i = 0; i < pattern.Length; i++)
        {
            char c = pattern[i];
            switch (c)
            {
                case '*':
                    if (i + 1 < pattern.Length && pattern[i + 1] == '*')
                    {
                        // ** matches everything including /
                        if (i + 2 < pattern.Length && pattern[i + 2] == '/')
                        {
                            regexPattern += "(.*/)?";
                            i += 2;
                        }
                        else
                        {
                            regexPattern += ".*";
                            i++;
                        }
                    }
                    else
                    {
                        // * matches everything except /
                        regexPattern += "[^/]*";
                    }

                    break;
                case '?':
                    regexPattern += "[^/]";
                    break;
                case '.':
                case '(':
                case ')':
                case '+':
                case '|':
                case '^':
                case '$':
                case '{':
                case '}':
                    regexPattern += "\\" + c;
                    break;
                case '[':
                    // character class - pass through to regex
                    var end = pattern.IndexOf(']', i);
                    if (end > i)
                    {
                        regexPattern += pattern[i..(end + 1)];
                        i = end;
                    }
                    else
                    {
                        regexPattern += "\\[";
                    }

                    break;
                default:
                    regexPattern += c;
                    break;
            }
        }

        if (!directoryOnly)
        {
            // Pattern can match a file directly or a directory prefix
            regexPattern += "(/.*)?$";
        }
        else
        {
            regexPattern += "/.*$";
        }

        return new Regex(regexPattern, RegexOptions.Compiled | RegexOptions.IgnoreCase);
    }

    internal record GitIgnoreRule(Regex Pattern, bool IsNegation, bool DirectoryOnly)
    {
        public bool IsMatch(string path)
        {
            return Pattern.IsMatch(path);
        }
    }
}
