using NuGetUpdater.Core.Updater;

namespace NuGetUpdater.Core.Test.Updater;

public record ExpectedUpdateOperationResult : UpdateOperationResult
{
    public string? ErrorDetailsRegex { get; init; } = null;
}
