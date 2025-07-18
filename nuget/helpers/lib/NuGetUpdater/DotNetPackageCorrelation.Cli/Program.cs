using System.CommandLine;
using System.Text.Json;

using DotNetPackageCorrelation;

namespace DotNetPackageCorrelation.Cli;

public class Program
{
    public static async Task<int> Main(string[] args)
    {
        var coreLocationOption = new Option<DirectoryInfo>("--core-location")
        {
            Description = "The location of the .NET Core source code.",
            Required = true
        };
        var outputOption = new Option<FileInfo>("--output")
        {
            Description = "The location to write the result.",
            Required = true
        };
        var command = new Command("build")
        {
            coreLocationOption,
            outputOption,
        };
        command.TreatUnmatchedTokensAsErrors = true;
        command.SetAction(async (parseResult, cancellationToken) =>
        {
            var coreLocationDirectory = parseResult.GetValue(coreLocationOption);
            var output = parseResult.GetValue(outputOption);

            // the tool is expected to be given the path to the .NET Core repository, but the correlator only needs a specific subdirectory
            var releaseNotesDirectory = new DirectoryInfo(Path.Combine(coreLocationDirectory!.FullName, "release-notes"));
            var correlator = new Correlator(releaseNotesDirectory);
            var (sdkPackages, _warnings) = await correlator.RunAsync();
            var json = JsonSerializer.Serialize(sdkPackages, Correlator.SerializerOptions);
            await File.WriteAllTextAsync(output!.FullName, json, cancellationToken);

            return 0;
        });
        var parseResult = command.Parse(args);
        var exitCode = await parseResult.InvokeAsync();
        return exitCode;
    }
}
