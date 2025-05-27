using System.Collections.Immutable;
using System.IO.Enumeration;
using System.Text.Json;
using System.Text.Json.Serialization;

using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;

namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record Job
{
    public string PackageManager { get; init; } = "nuget";
    public ImmutableArray<AllowedUpdate> AllowedUpdates { get; init; } = [new AllowedUpdate()];

    [JsonConverter(typeof(NullAsBoolConverter))]
    public bool Debug { get; init; } = false;
    public ImmutableArray<DependencyGroup> DependencyGroups { get; init; } = [];

    [JsonConverter(typeof(NullAsEmptyStringArrayConverter))]
    public ImmutableArray<string> Dependencies { get; init; } = [];
    public string? DependencyGroupToRefresh { get; init; } = null;
    public ImmutableArray<PullRequest> ExistingPullRequests { get; init; } = [];
    public ImmutableArray<GroupPullRequest> ExistingGroupPullRequests { get; init; } = [];
    public Dictionary<string, object>? Experiments { get; init; } = null;
    public Condition[] IgnoreConditions { get; init; } = [];
    public bool LockfileOnly { get; init; } = false;
    public RequirementsUpdateStrategy? RequirementsUpdateStrategy { get; init; } = null;
    public ImmutableArray<Advisory> SecurityAdvisories { get; init; } = [];
    public bool SecurityUpdatesOnly { get; init; } = false;
    public required JobSource Source { get; init; }
    public bool UpdateSubdependencies { get; init; } = false;
    public bool UpdatingAPullRequest { get; init; } = false;
    public bool VendorDependencies { get; init; } = false;
    public bool RejectExternalCode { get; init; } = false;
    public bool RepoPrivate { get; init; } = false;
    public CommitOptions? CommitMessageOptions { get; init; } = null;
    public ImmutableArray<Dictionary<string, object>>? CredentialsMetadata { get; init; } = null;
    public int MaxUpdaterRunTime { get; init; } = 0;

    public ImmutableArray<string> GetAllDirectories()
    {
        var builder = ImmutableArray.CreateBuilder<string>();
        if (Source.Directory is not null)
        {
            builder.Add(Source.Directory);
        }

        builder.AddRange(Source.Directories ?? []);
        if (builder.Count == 0)
        {
            builder.Add("/");
        }

        return builder.ToImmutable();
    }

    public ImmutableArray<DependencyGroup> GetRelevantDependencyGroups()
    {
        var appliesToKey = SecurityUpdatesOnly ? "security-updates" : "version-updates";
        var groups = DependencyGroups.Where(g => g.AppliesTo == appliesToKey)
            .ToImmutableArray();
        return groups;
    }

    public ImmutableArray<Tuple<string?, ImmutableArray<PullRequestDependency>>> GetAllExistingPullRequests()
    {
        var existingPullRequests = ExistingGroupPullRequests
            .Select(pr => Tuple.Create((string?)pr.DependencyGroupName, pr.Dependencies))
            .Concat(
                ExistingPullRequests
                .Select(pr => Tuple.Create((string?)null, pr.Dependencies)))
            .ToImmutableArray();
        return existingPullRequests;
    }

    public Tuple<string?, ImmutableArray<PullRequestDependency>>? GetExistingPullRequestForDependencies(IEnumerable<Dependency> dependencies, bool considerVersions)
    {
        if (dependencies.Any(d => d.Version is null))
        {
            return null;
        }

        string CreateIdentifier(string dependencyName, string dependencyVersion)
        {
            return $"{dependencyName}/{(considerVersions ? dependencyVersion : null)}";
        }

        var desiredDependencySet = dependencies.Select(d => CreateIdentifier(d.Name, d.Version!)).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var existingPullRequests = GetAllExistingPullRequests();
        var existingPullRequest = existingPullRequests
            .FirstOrDefault(pr =>
            {
                var prDependencySet = pr.Item2.Select(d => CreateIdentifier(d.DependencyName, d.DependencyVersion.ToString())).ToHashSet(StringComparer.OrdinalIgnoreCase);
                return prDependencySet.SetEquals(desiredDependencySet);
            });
        return existingPullRequest;
    }

    public bool IsDependencyIgnored(string dependencyName, string dependencyVersion)
    {
        var versionsToIgnore = IgnoreConditions
            .Where(c => FileSystemName.MatchesSimpleExpression(c.DependencyName, dependencyName))
            .Select(c => c.VersionRequirement ?? Requirement.Parse(">= 0.0.0")) // no range means ignore everything
            .ToArray();
        var parsedDependencyVersion = NuGetVersion.Parse(dependencyVersion);
        var isIgnored = versionsToIgnore
            .Any(r => r.IsSatisfiedBy(parsedDependencyVersion));
        return isIgnored;
    }
}

public class NullAsBoolConverter : JsonConverter<bool>
{
    public override bool Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Null)
        {
            return false;
        }

        return reader.GetBoolean();
    }

    public override void Write(Utf8JsonWriter writer, bool value, JsonSerializerOptions options)
    {
        writer.WriteBooleanValue(value);
    }
}

public class NullAsEmptyStringArrayConverter : JsonConverter<ImmutableArray<string>>
{
    public override ImmutableArray<string> Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Null)
        {
            return [];
        }

        return JsonSerializer.Deserialize<ImmutableArray<string>>(ref reader, options);
    }

    public override void Write(Utf8JsonWriter writer, ImmutableArray<string> value, JsonSerializerOptions options)
    {
        writer.WriteStartArray();
        writer.WriteEndArray();
    }
}
