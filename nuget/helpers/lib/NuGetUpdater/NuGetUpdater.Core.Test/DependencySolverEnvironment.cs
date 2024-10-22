namespace NuGetUpdater.Core.Test;

/// <summary>
/// Prepares the environment to use the new dependency solver.
/// </summary>
public class DependencySolverEnvironment : TemporaryEnvironment
{
    public DependencySolverEnvironment(bool useDependencySolver = true)
        : base([("UseNewNugetPackageResolver", useDependencySolver ? "true" : "false")])
    {
    }
}
