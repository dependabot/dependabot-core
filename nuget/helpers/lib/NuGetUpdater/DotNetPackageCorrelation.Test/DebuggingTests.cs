using Semver;

using Xunit;

namespace DotNetPackageCorrelation.Tests;

public class DebuggingTests
{
    [Fact]
    public async Task Debug_IntegrationTest()
    {
        // arrange
        var thisFileDirectory = Path.GetDirectoryName(GetThisFilePath())!;
        var dotnetCoreDirectory = Path.Combine(thisFileDirectory, "..", "..", "dotnet-core");
        var correlator = new Correlator(new DirectoryInfo(Path.Combine(dotnetCoreDirectory, "release-notes")));

        // act
        var (runtimePackages, warnings) = await correlator.RunAsync();

        // debug output
        Console.WriteLine($"Found {runtimePackages.Runtimes.Count} runtime packages");
        Console.WriteLine($"Warnings: {warnings.Count()}");

        foreach (var warning in warnings.Take(10))
        {
            Console.WriteLine($"Warning: {warning}");
        }

        // Check if 8.0.8 runtime exists
        var has808 = runtimePackages.Runtimes.TryGetValue(SemVersion.Parse("8.0.8"), out var packages808);
        Console.WriteLine($"Has 8.0.8 runtime: {has808}");

        if (has808)
        {
            Console.WriteLine($"Packages in 8.0.8: {packages808!.Packages.Count}");
            var refPackage = packages808.Packages.TryGetValue("Microsoft.NETCore.App.Ref", out var refVersion);
            Console.WriteLine($"Has Microsoft.NETCore.App.Ref in 8.0.8: {refPackage}, version: {refVersion}");
        }

        // Check if 8.0.7 runtime exists
        var has807 = runtimePackages.Runtimes.TryGetValue(SemVersion.Parse("8.0.7"), out var packages807);
        Console.WriteLine($"Has 8.0.7 runtime: {has807}");

        if (has807)
        {
            Console.WriteLine($"Packages in 8.0.7: {packages807!.Packages.Count}");
            var jsonPackage = packages807.Packages.TryGetValue("System.Text.Json", out var jsonVersion);
            Console.WriteLine($"Has System.Text.Json in 8.0.7: {jsonPackage}, version: {jsonVersion}");
        }

        var packageMapper = PackageMapper.Load(runtimePackages);

        // Test the specific case with more debug info
        Console.WriteLine("Testing GetPackageVersionThatShippedWithOtherPackage...");
        var systemTextJsonVersion = packageMapper.GetPackageVersionThatShippedWithOtherPackage("Microsoft.NETCore.App.Ref", SemVersion.Parse("8.0.8"), "System.Text.Json");
        Console.WriteLine($"Result: {systemTextJsonVersion}");

        // This is the assertion from the original test
        Assert.Equal("8.0.4", systemTextJsonVersion?.ToString());
    }

    private static string GetThisFilePath([System.Runtime.CompilerServices.CallerFilePath] string? path = null) => path ?? throw new ArgumentNullException(nameof(path));
}