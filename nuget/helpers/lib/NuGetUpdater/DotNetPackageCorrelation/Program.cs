using System.CommandLine;
using System.Text.Json;

namespace DotNetPackageCorrelation;

public class Program
{
    public static async Task<int> Main(string[] args)
    {
        var coreLocationOption = new Option<DirectoryInfo>("--core-location", "The location of the .NET Core source code.") { IsRequired = true };
        var outputOption = new Option<FileInfo>("--output", "The location to write the result.") { IsRequired = true };
        var command = new Command("build")
        {
            coreLocationOption,
            outputOption,
        };
        command.TreatUnmatchedTokensAsErrors = true;
        command.SetHandler(async (coreLocationDirectory, output) =>
        {
            // the tool is expected to be given the path to the .NET Core repository, but the correlator only needs a specific subdirectory
            var releaseNotesDirectory = new DirectoryInfo(Path.Combine(coreLocationDirectory.FullName, "release-notes"));
            var correlator = new Correlator(releaseNotesDirectory);
            var (packages, _warnings) = await correlator.RunAsync();
            var json = JsonSerializer.Serialize(packages, Correlator.SerializerOptions);
            await File.WriteAllTextAsync(output.FullName, json);
        }, coreLocationOption, outputOption);
        var exitCode = await command.InvokeAsync(args);
        return exitCode;
    }
}
