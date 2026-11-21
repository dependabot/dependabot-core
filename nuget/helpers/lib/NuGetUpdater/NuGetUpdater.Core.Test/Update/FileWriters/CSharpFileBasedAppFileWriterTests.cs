using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Updater.FileWriters;

using Xunit;

namespace NuGetUpdater.Core.Test.Update.FileWriters;

public class CSharpFileBasedAppFileWriterTests : FileWriterTestsBase
{
    public override IFileWriter FileWriter => new CSharpFileBasedAppFileWriter(new TestLogger());

    [Fact]
    public async Task UpdatesVersionedPackageDirective()
    {
        await TestAsync(
            files:
            [
                ("app.cs", """
                    #:package Ignored.Dependency@7.0.0
                    #:package Some.Dependency@1.0.0

                    Console.WriteLine("Hello");
                    """),
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles:
            [
                ("app.cs", """
                    #:package Ignored.Dependency@7.0.0
                    #:package Some.Dependency@2.0.0

                    Console.WriteLine("Hello");
                    """),
            ]);
    }

    [Fact]
    public async Task UpdatesOnlyPackageDirectivesBeforeCSharpCode()
    {
        await TestAsync(
            files:
            [
                ("app.cs", """"
                    #:package Some.Dependency@1.0.0

                    var text = """
                    #:package Some.Dependency@1.0.0
                    """;
                    """"),
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles:
            [
                ("app.cs", """"
                    #:package Some.Dependency@2.0.0

                    var text = """
                    #:package Some.Dependency@1.0.0
                    """;
                    """"),
            ]);
    }

    [Fact]
    public async Task UpdatesVersionedPackageDirectiveWithTrailingSuffix()
    {
        await TestAsync(
            files:
            [
                ("app.cs", """
                    #:package Some.Dependency@1.0.0 PrivateAssets=all OutputItemType=analyzer // existing comment

                    Console.WriteLine("Hello");
                    """),
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles:
            [
                ("app.cs", """
                    #:package Some.Dependency@2.0.0 PrivateAssets=all OutputItemType=analyzer // existing comment

                    Console.WriteLine("Hello");
                    """),
            ]);
    }

    [Fact]
    public async Task RejectsInvalidVersionWithTrailingCommentWithoutWhitespace()
    {
        await TestNoChangeAsync(
            files:
            [
                ("app.cs", """
                    #:package Some.Dependency@1.0.0// existing comment

                    Console.WriteLine("Hello");
                    """),
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"]);
    }

    [Fact]
    public async Task UpdatesVersionedPackageDirectiveWhenUnrelatedDependencyUsesWildcard()
    {
        await TestAsync(
            files:
            [
                ("app.cs", """
                    #:package Ignored.Dependency@*
                    #:package Some.Dependency@1.0.0

                    Console.WriteLine("Hello");
                    """),
            ],
            initialProjectDependencyStrings: ["Ignored.Dependency/*", "Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles:
            [
                ("app.cs", """
                    #:package Ignored.Dependency@*
                    #:package Some.Dependency@2.0.0

                    Console.WriteLine("Hello");
                    """),
            ]);
    }

    [Fact]
    public async Task RetainsWildcardVersionShape()
    {
        await TestAsync(
            files:
            [
                ("app.cs", """
                    #:package Some.Dependency@1.*

                    Console.WriteLine("Hello");
                    """),
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.3.4"],
            requiredDependencyStrings: ["Some.Dependency/2.5.6"],
            expectedFiles:
            [
                ("app.cs", """
                    #:package Some.Dependency@2.*

                    Console.WriteLine("Hello");
                    """),
            ]);
    }

    [Fact]
    public async Task LeavesSatisfiedAsteriskVersionDirectiveUnchanged()
    {
        await TestAsync(
            files:
            [
                ("app.cs", """
                    #:package Some.Dependency@*

                    Console.WriteLine("Hello");
                    """),
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles:
            [
                ("app.cs", """
                    #:package Some.Dependency@*

                    Console.WriteLine("Hello");
                    """),
            ]);
    }

    [Fact]
    public async Task PinsVersionlessPackageDirectiveWithoutCentralPackageManagement()
    {
        await TestAsync(
            files:
            [
                ("app.cs", """
                    #:package Some.Dependency

                    Console.WriteLine("Hello");
                    """),
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles:
            [
                ("app.cs", """
                    #:package Some.Dependency@2.0.0

                    Console.WriteLine("Hello");
                    """),
            ]);
    }

    [Fact]
    public async Task UpdatesCentralPackageVersionWithoutChangingDirective()
    {
        const string source = "#:package Some.Dependency PrivateAssets=all\nConsole.WriteLine();";
        const string centralFile = """
            <Project>
              <PropertyGroup>
                <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                <SomeVersion>1.0.0</SomeVersion>
              </PropertyGroup>
              <ItemGroup>
                <PackageVersion Include="Some.Dependency" Version="$(SomeVersion)" />
              </ItemGroup>
            </Project>
            """;
        await TestAsync(
            files: [("tools/app.cs", source), ("Directory.Packages.props", centralFile)],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [("tools/app.cs", source), ("Directory.Packages.props", centralFile.Replace("1.0.0", "2.0.0"))],
            packageManagementKind: PackageManagementKind.CentralPackageManagement,
            packageManagementSpecialFileRelativePath: "../Directory.Packages.props");
    }

    [Theory]
    [InlineData(PackageManagementKind.CentralPackageManagement)]
    [InlineData(PackageManagementKind.CentralPackageManagementWithTransitivePinning)]
    public async Task AddsSolverRequiredCentralPackageVersion(PackageManagementKind packageManagementKind)
    {
        const string source = "#:package Some.Dependency\n\nConsole.WriteLine();";
        await TestAsync(
            files:
            [
                ("app.cs", source),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """),
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0", "Transitive.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/1.0.0", "Transitive.Dependency/2.0.0"],
            expectedFiles:
            [
                ("app.cs", packageManagementKind == PackageManagementKind.CentralPackageManagement
                    ? "#:package Some.Dependency\n#:package Transitive.Dependency\n\nConsole.WriteLine();"
                    : source),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                        <PackageVersion Include="Transitive.Dependency" Version="2.0.0" />
                      </ItemGroup>
                    </Project>
                    """),
            ],
            packageManagementKind: packageManagementKind,
            packageManagementSpecialFileRelativePath: "Directory.Packages.props");
    }

    [Fact]
    public async Task MissingCentralVersionDoesNotReportSuccessOrPartiallyWriteFiles()
    {
        await TestNoChangeAsync(
            files:
            [
                ("app.cs", "#:package Some.Dependency\n#:package Missing.Dependency\nConsole.WriteLine();"),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """),
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0", "Missing.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0", "Missing.Dependency/2.0.0"],
            packageManagementKind: PackageManagementKind.CentralPackageManagement,
            packageManagementSpecialFileRelativePath: "Directory.Packages.props");
    }

    [Fact]
    public async Task AddsSolverRequiredPackageDirective()
    {
        await TestAsync(
            files:
            [
                ("app.cs", """
                    #:package Some.Dependency@1.0.0

                    Console.WriteLine("Hello");
                    """),
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0", "Transitive.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0", "Transitive.Dependency/3.0.0"],
            expectedFiles:
            [
                ("app.cs", """
                    #:package Some.Dependency@2.0.0
                    #:package Transitive.Dependency@3.0.0

                    Console.WriteLine("Hello");
                    """),
            ]);
    }

    [Fact]
    public async Task SkipsUnparseableRequiredDependencyVersions()
    {
        await TestNoChangeAsync(
            files:
            [
                 ("app.cs", """
                    #:package Some.Dependency@1.0.0

                    Console.WriteLine("Hello");
                    """),
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/not-a-version"]);
    }
}
