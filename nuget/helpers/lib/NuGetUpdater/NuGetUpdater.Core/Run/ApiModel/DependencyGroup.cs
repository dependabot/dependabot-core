using System.Collections.Immutable;
using System.IO.Enumeration;

namespace NuGetUpdater.Core.Run.ApiModel;

public record DependencyGroup
{
    public required string Name { get; init; }
    public string? AppliesTo { get; init; }

    // TODO: make more strongly typed, but currently this seems to be:
    //   "patterns" => string[] where each element is a wildcard name pattern
    //   "exclude-patterns"=> string[] where each element is a wildcard name pattern
    //   "dependency-type" => production|development // not used for nuget?
    public Dictionary<string, object> Rules { get; init; } = new();

    public GroupMatcher GetGroupMatcher() => GroupMatcher.FromRules(Rules);
}

public class GroupMatcher
{
    public ImmutableArray<string> Patterns { get; init; } = ImmutableArray<string>.Empty;
    public ImmutableArray<string> ExcludePatterns { get; init; } = ImmutableArray<string>.Empty;

    public bool IsMatch(string dependencyName)
    {
        var isIncluded = Patterns.Any(p => FileSystemName.MatchesSimpleExpression(p, dependencyName));
        var isExcluded = ExcludePatterns.Any(p => FileSystemName.MatchesSimpleExpression(p, dependencyName));
        var isMatch = isIncluded && !isExcluded;
        return isMatch;
    }

    public static GroupMatcher FromRules(Dictionary<string, object> rules)
    {
        string[] patterns;
        if (rules.TryGetValue("patterns", out var patternsObject) &&
            patternsObject is string[] patternsArray)
        {
            patterns = patternsArray;
        }
        else
        {
            patterns = ["*"]; // default to matching everything unless excluded below
        }

        string[] excludePatterns;
        if (rules.TryGetValue("exclude-patterns", out var excludePatternsObject) &&
            excludePatternsObject is string[] excludePatternsArray)
        {
            excludePatterns = excludePatternsArray;
        }
        else
        {
            excludePatterns = [];
        }

        return new GroupMatcher()
        {
            Patterns = [.. patterns],
            ExcludePatterns = [.. excludePatterns],
        };
    }
}

public static class DependencyGroupExtensions
{
    public static bool IsSecurity(this DependencyGroup group) => group.AppliesTo == "security-updates";
}
