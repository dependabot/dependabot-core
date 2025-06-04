using System.Collections.Immutable;

namespace NuGetUpdater.Core.Updater;

public record UpdateOperationResult : NativeResult
{
    public required ImmutableArray<UpdateOperationBase> UpdateOperations { get; init; }
}
