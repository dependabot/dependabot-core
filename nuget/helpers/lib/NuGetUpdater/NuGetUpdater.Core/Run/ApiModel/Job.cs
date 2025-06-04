using System.Collections.Immutable;
using System.IO.Enumeration;
using System.Text.Json;
using System.Text.Json.Serialization;

using Microsoft.Extensions.FileSystemGlobbing;

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

    public bool IsUpdatePermitted(Dependency dependency)
    {
        if (dependency.Version is null)
        {
            // if we don't know the version, there's nothing we can do
            return false;
        }

        var version = NuGetVersion.Parse(dependency.Version);
        var dependencyInfo = RunWorker.GetDependencyInfo(this, dependency);
        var isVulnerable = dependencyInfo.Vulnerabilities.Any(v => v.IsVulnerable(version));

        bool IsAllowed(AllowedUpdate allowedUpdate)
        {
            // check name restriction, if any
            if (allowedUpdate.DependencyName is not null)
            {
                var matcher = new Matcher(StringComparison.OrdinalIgnoreCase)
                    .AddInclude(allowedUpdate.DependencyName);
                var result = matcher.Match(dependency.Name);
                if (!result.HasMatches)
                {
                    return false;
                }
            }

            var isSecurityUpdate = allowedUpdate.UpdateType == UpdateType.Security || SecurityUpdatesOnly;
            if (isSecurityUpdate)
            {
                if (isVulnerable)
                {
                    // try to match to existing PR
                    var dependencyVersion = NuGetVersion.Parse(dependency.Version);
                    var existingPullRequests = GetAllExistingPullRequests()
                        .Where(pr => pr.Item2.Any(d => d.DependencyName.Equals(dependency.Name, StringComparison.OrdinalIgnoreCase) && d.DependencyVersion >= dependencyVersion))
                        .ToArray();
                    if (existingPullRequests.Length > 0)
                    {
                        // found a matching pr...
                        if (UpdatingAPullRequest)
                        {
                            // ...and we've been asked to update it
                            return true;
                        }
                        else
                        {
                            // ...but no update requested => don't perform any update
                            return false;
                        }
                    }
                    else
                    {
                        // no matching pr...
                        if (UpdatingAPullRequest)
                        {
                            // ...but we've been asked to perform an update => no update possible
                            return false;
                        }
                        else
                        {
                            // ...and no update specifically requested => create new
                            return true;
                        }
                    }
                }

                return false;
            }
            else
            {
                // not a security update, so only update if...
                // ...we've been explicitly asked to update this
                if (Dependencies.Any(d => d.Equals(dependency.Name, StringComparison.OrdinalIgnoreCase)))
                {
                    return true;
                }

                // ...no specific update being performed, do it if it's not transitive
                return !dependency.IsTransitive;
            }
        }

        var allowed = AllowedUpdates.Any(IsAllowed);
        return allowed;
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
