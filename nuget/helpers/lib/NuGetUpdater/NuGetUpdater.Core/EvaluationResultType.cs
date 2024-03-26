namespace NuGetUpdater.Core;

public enum EvaluationResultType
{
    Success,
    PropertyIgnored,
    CircularReference,
    PropertyNotFound,
}
