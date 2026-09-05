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
    public async Task LeavesVersionlessPackageDirectiveUnchanged()
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
                    #:package Some.Dependency

                    Console.WriteLine("Hello");
                    """),
            ]);
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
