using Semver;

using Xunit;

namespace DotNetPackageCorrelation.Tests;

public class CorrelatorTests
{
    [Fact]
    public async Task FileHandling_AllFilesShapedAppropriately()
    {
        // the JSON and markdown are shaped as expected
        // we're able to determine from `Runtime.Package/8.0.0` that the corresponding version of `Some.Package` is `1.2.3`
        var (packageMapper, warnings) = await PackageMapperFromFilesAsync(
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
                Runtime.Package | 8.0.0
                Some.Package | 1.2.3
                """)
        );
        Assert.Empty(warnings);
        AssertPackageVersion(packageMapper, "Runtime.Package", "8.0.0", "Some.Package", "1.2.3");
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

    private static void AssertPackageVersion(PackageMapper packageMapper, string runtimePackageName, string runtimePackageVersion, string candidatePackageName, string? expectedPackageVersion)
    {
        var actualPackageVersion = packageMapper.GetPackageVersionThatShippedWithOtherPackage(runtimePackageName, SemVersion.Parse(runtimePackageVersion), candidatePackageName);
        if (expectedPackageVersion is null)
        {
            Assert.Null(actualPackageVersion);
        }
        else
        {
            Assert.NotNull(actualPackageVersion);
            Assert.Equal(expectedPackageVersion, actualPackageVersion.ToString());
        }
    }

    private static async Task<(PackageMapper PackageMapper, IEnumerable<string> Warnings)> PackageMapperFromFilesAsync(params (string Path, string Content)[] files)
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
            var (runtimePackages, warnings) = await correlator.RunAsync();
            var packageMapper = PackageMapper.Load(runtimePackages);
            return (packageMapper, warnings);
        }
        finally
        {
            Directory.Delete(testDirectory, recursive: true);
        }
    }
}
