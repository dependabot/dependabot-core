using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Serialization;

using NuGet.Credentials;
using NuGet.Versioning;

namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record Job
{
    public string PackageManager { get; init; } = "nuget";
    public ImmutableArray<AllowedUpdate> AllowedUpdates { get; init; } = [new AllowedUpdate()];

    [JsonConverter(typeof(NullAsBoolConverter))]
    public bool Debug { get; init; } = false;
    public ImmutableArray<DependencyGroup> DependencyGroups { get; init; } = [];
    public ImmutableArray<string>? Dependencies { get; init; } = null;
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
    public ImmutableArray<Dictionary<string, string>>? CredentialsMetadata { get; init; } = null;
    public int MaxUpdaterRunTime { get; init; } = 0;

    public IEnumerable<string> GetAllDirectories()
    {
        var returnedADirectory = false;
        if (Source.Directory is not null)
        {
            returnedADirectory = true;
            yield return Source.Directory;
        }

        foreach (var directory in Source.Directories ?? [])
        {
            returnedADirectory = true;
            yield return directory;
        }

        if (!returnedADirectory)
        {
            yield return "/";
        }
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

    public Tuple<string?, ImmutableArray<PullRequestDependency>>? GetExistingPullRequestForDependency(Dependency dependency)
    {
        if (dependency.Version is null)
        {
            return null;
        }

        var dependencyVersion = NuGetVersion.Parse(dependency.Version);
        var existingPullRequests = GetAllExistingPullRequests();
        var existingPullRequest = existingPullRequests.FirstOrDefault(pr =>
        {
            if (pr.Item2.Length == 1 &&
                pr.Item2[0].DependencyName.Equals(dependency.Name, StringComparison.OrdinalIgnoreCase) &&
                pr.Item2[0].DependencyVersion == dependencyVersion)
            {
                return true;
            }

            return false;
        });
        return existingPullRequest;
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
