using Semver;

using Xunit;

namespace DotNetPackageCorrelation.Tests;

public class CorrelatorTests
{
    [Fact]
    public async Task FileHandling_AllFilesShapedAppropriately()
    {
        // the JSON and markdown are shaped as expected
        var (packages, warnings) = await RunFromFilesAsync(
            ("8.0/releases.json", """
                {
                    "releases": [
                        {
                            "sdk": {
                                "version": "8.0.100",
                                "runtime-version": "8.0.0"
                            }
                        }
                    ]
                }
                """),
            ("8.0/8.0.0/8.0.0.md", """
                Package name | Version
                :-- | :--
                Package.A | 8.0.0
                Package.B | 1.2.3
                """)
        );
        Assert.Empty(warnings);
        AssertPackageVersion(packages, "8.0.100", "Package.A", "8.0.0");
        AssertPackageVersion(packages, "8.0.100", "Package.B", "1.2.3");
    }

    [Theory]
    [InlineData("Some.Package | 1.2.3", "Some.Package", "1.2.3")] // happy path
    [InlineData("Some.Package.1.2.3", "Some.Package", "1.2.3")] // looks like a restore directory
    [InlineData("Some.Package | 1.2 | 1.2.3.nupkg", "Some.Package", "1.2.3")] // extra columns from a bad filename split
    [InlineData("Some.Package | 1.2.3.nupkg", "Some.Package", "1.2.3")] // version contains package extension
    [InlineData("Some.Package | 1.2.3.symbols.nupkg", "Some.Package", "1.2.3")] // version contains symbols package extension
    [InlineData("some.package.1.2.3.nupkg", "some.package", "1.2.3")] // first column is a filename, second column is missing
    [InlineData("some.package.1.2.3.nupkg |", "some.package", "1.2.3")] // first column is a filename, second column is empty
    public void PackagesParsedFromMarkdown(string markdownLine, string expectedPackageName, string expectedPackageVersion)
    {
        var markdownContent = $"""
            Package name | Version
            :-- | :--
            {markdownLine}
            """;
        var warnings = new List<string>();
        var packages = Correlator.GetPackagesFromMarkdown("test.md", markdownContent, warnings);
        Assert.Empty(warnings);
        var actualpackage = Assert.Single(packages);
        Assert.Equal(expectedPackageName, actualpackage.Name);
        Assert.Equal(expectedPackageVersion, actualpackage.Version.ToString());
    }

    private static void AssertPackageVersion(SdkPackages packages, string sdkVersion, string packageName, string expectedPackageVersion)
    {
        Assert.True(packages.Packages.TryGetValue(SemVersion.Parse(sdkVersion), out var packageSet), $"Unable to find SDK version [{sdkVersion}]");
        Assert.True(packageSet.Packages.TryGetValue(packageName, out var packageVersion), $"Unable to find package [{packageName}] under SDK version [{sdkVersion}]");
        var actualPackageVersion = packageVersion.ToString();
        Assert.Equal(expectedPackageVersion, actualPackageVersion);
    }

    private static async Task<(SdkPackages Packages, IEnumerable<string> Warnings)> RunFromFilesAsync(params (string Path, string Content)[] files)
    {
        var testDirectory = Path.Combine(Path.GetDirectoryName(typeof(CorrelatorTests).Assembly.Location)!, "test-data", Guid.NewGuid().ToString("D"));
        Directory.CreateDirectory(testDirectory);

        try
        {
            foreach (var (path, content) in files)
            {
                var fullPath = Path.Combine(testDirectory, path);
                Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
                await File.WriteAllTextAsync(fullPath, content);
            }

            var correlator = new Correlator(new DirectoryInfo(testDirectory));
            var result = await correlator.RunAsync();
            return result;
        }
        finally
        {
            Directory.Delete(testDirectory, recursive: true);
        }
    }
}
