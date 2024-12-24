namespace NuGetUpdater.Core;

public enum ErrorType
{
    None,
    AuthenticationFailure,
    MissingFile,
    UpdateNotPossible,
    DependencyFileNotParseable,
    Unknown,
}
