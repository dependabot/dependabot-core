namespace NuGetUpdater.Core;

internal class BadRequirementException : Exception
{
    public BadRequirementException(string details)
        : base(details)
    {
    }
}
