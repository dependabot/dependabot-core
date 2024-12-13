using System.Collections.Immutable;

namespace NuGetUpdater.Core.Run.ApiModel;

public record GroupPullRequest
{
    public required string DependencyGroupName { get; init; }
    public required ImmutableArray<PullRequest> Dependencies { get; init; }
}
