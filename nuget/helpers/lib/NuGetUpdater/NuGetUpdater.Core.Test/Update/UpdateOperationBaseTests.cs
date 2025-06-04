using NuGet.Versioning;

using NuGetUpdater.Core.Test.Utilities;
using NuGetUpdater.Core.Updater;

using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public class UpdateOperationBaseTests
{
    [Fact]
    public void GetReport()
    {
        // arrange
        var updateOperations = new UpdateOperationBase[]
        {
            new DirectUpdate()
            {
                DependencyName = "Package.A",
                NewVersion = NuGetVersion.Parse("1.0.0"),
                UpdatedFiles = ["file/a.txt"]
            },
            new DirectUpdate()
            {
                DependencyName = "Package.B",
                OldVersion = NuGetVersion.Parse("0.2.0"),
                NewVersion = NuGetVersion.Parse("2.0.0"),
                UpdatedFiles = ["file/b.txt"]
            },
            new PinnedUpdate()
            {
                DependencyName = "Package.C",
                OldVersion = NuGetVersion.Parse("0.3.0"),
                NewVersion = NuGetVersion.Parse("3.0.0"),
                UpdatedFiles = ["file/c.txt"]
            },
            new ParentUpdate()
            {
                DependencyName = "Package.D",
                OldVersion = NuGetVersion.Parse("0.4.0"),
                NewVersion = NuGetVersion.Parse("4.0.0"),
                UpdatedFiles = ["file/d.txt"],
                ParentDependencyName = "Package.E",
                ParentNewVersion = NuGetVersion.Parse("5.0.0"),
            },
        };

        // act
        var actualReport = UpdateOperationBase.GenerateUpdateOperationReport(updateOperations);

        // assert
        var expectedReport = """
            Performed the following updates:
            - Updated Package.A to 1.0.0 in file/a.txt
            - Updated Package.B from 0.2.0 to 2.0.0 in file/b.txt
            - Pinned Package.C at 3.0.0 in file/c.txt
            - Updated Package.D to 4.0.0 indirectly via Package.E/5.0.0 in file/d.txt
            """.Replace("\r", "");
        Assert.Equal(expectedReport, actualReport);
    }

    [Fact]
    public void NormalizeUpdateOperationCollection_SortAndDistinct()
    {
        // arrange
        var repoRootPath = "/repo/root";
        var updateOperations = new UpdateOperationBase[]
        {
            new DirectUpdate()
            {
                DependencyName = "Dependency.Direct",
                OldVersion = NuGetVersion.Parse("0.1.0"),
                NewVersion = NuGetVersion.Parse("1.0.0"),
                UpdatedFiles = ["/repo/root/file/a.txt"]
            },
            new PinnedUpdate()
            {
                DependencyName = "Dependency.Pinned",
                OldVersion = NuGetVersion.Parse("0.2.0"),
                NewVersion = NuGetVersion.Parse("2.0.0"),
                UpdatedFiles = ["/repo/root/file/b.txt"]
            },
            // this is the same as the first item and will be removed
            new DirectUpdate()
            {
                DependencyName = "Dependency.Direct",
                OldVersion = NuGetVersion.Parse("0.1.0"),
                NewVersion = NuGetVersion.Parse("1.0.0"),
                UpdatedFiles = ["/repo/root/file/a.txt"]
            },
            new ParentUpdate()
            {
                DependencyName = "Dependency.Parent",
                OldVersion = NuGetVersion.Parse("0.3.0"),
                NewVersion = NuGetVersion.Parse("3.0.0"),
                UpdatedFiles = ["/repo/root/file/c.txt"],
                ParentDependencyName = "Dependency.Root",
                ParentNewVersion = NuGetVersion.Parse("4.0.0"),
            },
        };

        // act
        var normalizedOperations = UpdateOperationBase.NormalizeUpdateOperationCollection(repoRootPath, updateOperations);
        var normalizedDependencyNames = string.Join(", ", normalizedOperations.Select(o => o.DependencyName));

        // assert
        var expectedDependencyNames = "Dependency.Direct, Dependency.Parent, Dependency.Pinned";
        Assert.Equal(expectedDependencyNames, normalizedDependencyNames);
    }

    [Fact]
    public void NormalizeUpdateOperationCollection_CombinedOnTypeAndDependency()
    {
        // arrange
        var repoRootPath = "/repo/root";
        var updateOperations = new UpdateOperationBase[]
        {
            // both operations are the same type, same dependency, same version => files are combined
            new DirectUpdate()
            {
                DependencyName = "Dependency.Direct",
                OldVersion = NuGetVersion.Parse("0.1.0"),
                NewVersion = NuGetVersion.Parse("1.0.0"),
                UpdatedFiles = ["/repo/root/file/b.txt"]
            },
            new DirectUpdate()
            {
                DependencyName = "Dependency.Direct",
                OldVersion = NuGetVersion.Parse("0.1.0"),
                NewVersion = NuGetVersion.Parse("1.0.0"),
                UpdatedFiles = ["/repo/root/file/a.txt"]
            },
        };

        // act
        var normalizedOperations = UpdateOperationBase.NormalizeUpdateOperationCollection(repoRootPath, updateOperations);

        // assert
        var singleUpdate = Assert.Single(normalizedOperations);
        var directUpdate = Assert.IsType<DirectUpdate>(singleUpdate);
        Assert.Equal("Dependency.Direct", directUpdate.DependencyName);
        Assert.Equal(NuGetVersion.Parse("1.0.0"), directUpdate.NewVersion);
        AssertEx.Equal(["/file/a.txt", "/file/b.txt"], directUpdate.UpdatedFiles);
    }
}
