using NuGetUpdater.Core.Analyze;

namespace NuGetUpdater.Core.Test.Analyze;

public record ExpectedAnalysisResult : AnalysisResult
{
    public int? ExpectedUpdatedDependenciesCount { get; init; }
}
