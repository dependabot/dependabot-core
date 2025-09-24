using System.Collections.Immutable;
using System.IO.Enumeration;
using System.Text.Json;

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
        var patterns = GetStringArray(rules, "patterns", ["*"]); // default to matching everything unless explicitly excluded
        var excludePatterns = GetStringArray(rules, "exclude-patterns", []);

        return new GroupMatcher()
        {
            Patterns = patterns,
            ExcludePatterns = excludePatterns,
        };
    }

    private static ImmutableArray<string> GetStringArray(Dictionary<string, object> rules, string propertyName, ImmutableArray<string> defaultValue)
    {
        if (!rules.TryGetValue(propertyName, out var propertyObject))
        {
            return defaultValue;
        }

        if (propertyObject is string[] stringArray)
        {
            // shortcut for unit tests which directly supply the array
            return [.. stringArray];
        }

        var patternsElements = new List<string>();
        if (propertyObject is JsonElement element &&
            element.ValueKind == JsonValueKind.Array)
        {
            foreach (var arrayElement in element.EnumerateArray())
            {
                if (arrayElement.ValueKind == JsonValueKind.String)
                {
                    patternsElements.Add(arrayElement.GetString()!);
                }
            }
        }

        return [.. patternsElements];
    }
}

public static class DependencyGroupExtensions
{
    public static bool IsSecurity(this DependencyGroup group) => group.AppliesTo == "security-updates";
}
