namespace NuGetUpdater.Core;

public enum ErrorType
{
    // TODO: add `Unknown` option to track all other failure types
    None,
    AuthenticationFailure,
    MissingFile,
}
