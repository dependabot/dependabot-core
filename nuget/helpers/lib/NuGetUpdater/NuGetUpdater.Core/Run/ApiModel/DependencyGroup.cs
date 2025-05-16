using System.IO.Enumeration;

namespace NuGetUpdater.Core.Run.ApiModel;

public record DependencyGroup
{
    public required string Name { get; init; }
    public string? AppliesTo { get; init; }

    // TODO: make more tightly coupled, but currently this seems to be:
    //   "patterns" => string[] where each element is a wildcard name pattern
    //   "exclude-patterns"=> string[] where each element is a wildcard name pattern
    //   "dependency-type" => production|development // not used for nuget?
    public Dictionary<string, object> Rules { get; init; } = new();
}

public static class DependencyGroupExtensions
{
    public static bool IsSecurity(this DependencyGroup group) => group.AppliesTo == "security-updates";

    public static bool IsMatch(this DependencyGroup group, string dependencyName)
    {
        string[] patterns;
        if (group.Rules.TryGetValue("patterns", out var patternsObject) &&
            patternsObject is string[] patternsArray)
        {
            patterns = patternsArray;
        }
        else
        {
            patterns = ["*"]; // default to matching everything unless excluded below
        }

        string[] excludePatterns;
        if (group.Rules.TryGetValue("exclude-patterns", out var excludePatternsObject) &&
            excludePatternsObject is string[] excludePatternsArray)
        {
            excludePatterns = excludePatternsArray;
        }
        else
        {
            excludePatterns = [];
        }

        var isIncluded = patterns.Any(p => FileSystemName.MatchesSimpleExpression(p, dependencyName));
        var isExcluded = excludePatterns.Any(p => FileSystemName.MatchesSimpleExpression(p, dependencyName));
        var isMatch = isIncluded && !isExcluded;
        return isMatch;
    }
}
