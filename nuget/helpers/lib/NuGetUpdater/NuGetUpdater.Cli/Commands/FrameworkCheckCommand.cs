using System;
using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.FrameworkChecker;

namespace NuGetUpdater.Cli.Commands;

internal static class FrameworkCheckCommand
{
    internal static readonly Option<string[]> ProjectTfmsOption = new("--project-tfms") { IsRequired = true, AllowMultipleArgumentsPerToken = true };
    internal static readonly Option<string[]> PackageTfmsOption = new("--package-tfms") { IsRequired = true, AllowMultipleArgumentsPerToken = true };
    internal static readonly Option<bool> VerboseOption = new("--verbose", getDefaultValue: () => false);

    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("framework-check", "Checks that a project's target frameworks are satisfied by the target frameworks supported by a package.")
        {
            ProjectTfmsOption,
            PackageTfmsOption,
            VerboseOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetHandler((projectTfms, packageTfms, verbose) =>
        {
            setExitCode(CompatibilityChecker.IsCompatible(projectTfms, packageTfms, new Logger(verbose))
                ? 0
                : 1);
        }, ProjectTfmsOption, PackageTfmsOption, VerboseOption);

        return command;
    }
}
