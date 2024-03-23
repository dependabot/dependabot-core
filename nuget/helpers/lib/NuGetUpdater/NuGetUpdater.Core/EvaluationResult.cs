namespace NuGetUpdater.Core;

public record EvaluationResult(
    EvaluationResultType ResultType,
    string OriginalValue,
    string EvaluatedValue,
    string? RootPropertyName,
    string? ErrorMessage);
