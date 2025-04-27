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
            new PinnedUpdate()
            {
                DependencyName = "Package.B",
                NewVersion = NuGetVersion.Parse("2.0.0"),
                UpdatedFiles = ["file/b.txt"]
            },
            new ParentUpdate()
            {
                DependencyName = "Package.C",
                NewVersion = NuGetVersion.Parse("3.0.0"),
                UpdatedFiles = ["file/c.txt"],
                ParentDependencyName = "Package.D",
                ParentNewVersion = NuGetVersion.Parse("4.0.0"),
            },
        };

        // act
        var actualReport = UpdateOperationBase.GenerateUpdateOperationReport(updateOperations);

        // assert
        var expectedReport = """
            Performed the following updates:
            - Updated Package.A to 1.0.0 in file/a.txt
            - Pinned Package.B at 2.0.0 in file/b.txt
            - Updated Package.C to 3.0.0 indirectly via Package.D/4.0.0 in file/c.txt
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
                NewVersion = NuGetVersion.Parse("1.0.0"),
                UpdatedFiles = ["/repo/root/file/a.txt"]
            },
            new PinnedUpdate()
            {
                DependencyName = "Dependency.Pinned",
                NewVersion = NuGetVersion.Parse("2.0.0"),
                UpdatedFiles = ["/repo/root/file/b.txt"]
            },
            // this is the same as the first item and will be removed
            new DirectUpdate()
            {
                DependencyName = "Dependency.Direct",
                NewVersion = NuGetVersion.Parse("1.0.0"),
                UpdatedFiles = ["/repo/root/file/a.txt"]
            },
            new ParentUpdate()
            {
                DependencyName = "Dependency.Parent",
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
                NewVersion = NuGetVersion.Parse("1.0.0"),
                UpdatedFiles = ["/repo/root/file/b.txt"]
            },
            new DirectUpdate()
            {
                DependencyName = "Dependency.Direct",
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
