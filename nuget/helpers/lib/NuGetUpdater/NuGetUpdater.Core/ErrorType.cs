namespace NuGetUpdater.Core;

public enum ErrorType
{
    None,
    AuthenticationFailure,
    BadRequirement,
    MissingFile,
    UpdateNotPossible,
    DependencyFileNotParseable,
    Unknown,
}
