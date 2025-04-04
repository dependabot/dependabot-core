using System.Collections.Immutable;

namespace NuGetUpdater.Core.Run.ApiModel;

public record PullRequest
{
    public ImmutableArray<PullRequestDependency> Dependencies { get; init; } = [];
}
