namespace NuGetUpdater.Core;

public record NativeResult
{
    // TODO: nullable not required, `ErrorType.None` is the default anyway
    public ErrorType? ErrorType { get; init; }
    public string? ErrorDetails { get; init; }
}
