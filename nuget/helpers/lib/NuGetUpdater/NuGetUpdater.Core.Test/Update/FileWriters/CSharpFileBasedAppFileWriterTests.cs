using System.Text;

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
    public async Task UpdatesVersionedPackageDirectiveWithTrailingComment()
    {
        await TestAsync(
            files:
            [
                ("app.cs", """
                    #:package Some.Dependency@1.0.0 // existing comment

                    Console.WriteLine("Hello");
                    """),
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles:
            [
                ("app.cs", """
                    #:package Some.Dependency@2.0.0 // existing comment

                    Console.WriteLine("Hello");
                    """),
            ]);
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
    public async Task PreservesUtf8BomWhenUpdatingVersionedPackageDirective()
    {
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync();
        var filePath = Path.Combine(tempDir.DirectoryPath, "app.cs");
        await File.WriteAllTextAsync(filePath, """
            #!/usr/bin/env dotnet run
            #:package Some.Dependency@1.0.0

            Console.WriteLine("Hello");
            """, new UTF8Encoding(encoderShouldEmitUTF8Identifier: true), TestContext.Current.CancellationToken);

        var success = await FileWriter.UpdatePackageVersionsAsync(
            new DirectoryInfo(tempDir.DirectoryPath),
            ["app.cs"],
            [new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference)],
            [new Dependency("Some.Dependency", "2.0.0", DependencyType.PackageReference)],
            PackageManagementKind.Default);

        Assert.True(success, "Expected UpdatePackageVersionsAsync to succeed.");
        var updatedBytes = await File.ReadAllBytesAsync(filePath, TestContext.Current.CancellationToken);
        var preamble = new UTF8Encoding(encoderShouldEmitUTF8Identifier: true).GetPreamble();
        Assert.True(updatedBytes.AsSpan(0, preamble.Length).SequenceEqual(preamble));

        var updatedContents = await File.ReadAllTextAsync(filePath, TestContext.Current.CancellationToken);
        Assert.Equal("""
            #!/usr/bin/env dotnet run
            #:package Some.Dependency@2.0.0

            Console.WriteLine("Hello");
            """.Replace("\r", ""), updatedContents.Replace("\r", ""));
    }

    [Fact]
    public async Task LeavesVersionlessPackageDirectiveUnchanged()
    {
        await TestNoChangeAsync(
            files:
            [
                ("app.cs", """
                    #:package Some.Dependency

                    Console.WriteLine("Hello");
                    """),
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"]);
    }
}
