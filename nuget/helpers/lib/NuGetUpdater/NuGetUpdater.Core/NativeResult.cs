using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core;

public record NativeResult
{
    public JobErrorBase? Error { get; init; } = null;
}
