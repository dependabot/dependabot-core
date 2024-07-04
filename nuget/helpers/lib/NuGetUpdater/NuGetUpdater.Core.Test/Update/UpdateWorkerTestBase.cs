using Xunit;

namespace NuGetUpdater.Core.Test.Update;

using TestFile = (string Path, string Content);
using TestProject = (string Path, string Content, Guid ProjectId);

public abstract class UpdateWorkerTestBase : TestBase
{
    protected static Task TestNoChange(
        string dependencyName,
        string oldVersion,
        string newVersion,
        bool useSolution,
        string projectContents,
        bool isTransitive = false,
        TestFile[]? additionalFiles = null,
        MockNuGetPackage[]? packages = null,
        string projectFilePath = "test-project.csproj")
    {
        return useSolution
            ? TestNoChangeforSolution(dependencyName, oldVersion, newVersion, projectFiles: [(projectFilePath, projectContents)], isTransitive, additionalFiles, packages)
            : TestNoChangeforProject(dependencyName, oldVersion, newVersion, projectContents, isTransitive, additionalFiles, packages, projectFilePath);
    }

    protected static Task TestUpdate(
        string dependencyName,
        string oldVersion,
        string newVersion,
        bool useSolution,
        string projectContents,
        string expectedProjectContents,
        bool isTransitive = false,
        TestFile[]? additionalFiles = null,
        TestFile[]? additionalFilesExpected = null,
        MockNuGetPackage[]? packages = null,
        string projectFilePath = "test-project.csproj")
    {
        return useSolution
            ? TestUpdateForSolution(dependencyName, oldVersion, newVersion, projectFiles: [(projectFilePath, projectContents)], projectFilesExpected: [(projectFilePath, expectedProjectContents)], isTransitive, additionalFiles, additionalFilesExpected, packages)
            : TestUpdateForProject(dependencyName, oldVersion, newVersion, projectFile: (projectFilePath, projectContents), expectedProjectContents, isTransitive, additionalFiles, additionalFilesExpected, packages);
    }

    protected static Task TestUpdate(
        string dependencyName,
        string oldVersion,
        string newVersion,
        bool useSolution,
        TestFile projectFile,
        string expectedProjectContents,
        bool isTransitive = false,
        TestFile[]? additionalFiles = null,
        TestFile[]? additionalFilesExpected = null,
        MockNuGetPackage[]? packages = null)
    {
        return useSolution
            ? TestUpdateForSolution(dependencyName, oldVersion, newVersion, projectFiles: [projectFile], projectFilesExpected: [(projectFile.Path, expectedProjectContents)], isTransitive, additionalFiles, additionalFilesExpected, packages)
            : TestUpdateForProject(dependencyName, oldVersion, newVersion, projectFile, expectedProjectContents, isTransitive, additionalFiles, additionalFilesExpected, packages);
    }

    protected static Task TestNoChangeforProject(
        string dependencyName,
        string oldVersion,
        string newVersion,
        string projectContents,
        bool isTransitive = false,
        TestFile[]? additionalFiles = null,
        MockNuGetPackage[]? packages = null,
        string projectFilePath = "test-project.csproj")
        => TestUpdateForProject(
            dependencyName,
            oldVersion,
            newVersion,
            (projectFilePath, projectContents),
            expectedProjectContents: projectContents,
            isTransitive,
            additionalFiles,
            additionalFilesExpected: additionalFiles,
            packages: packages);

    protected static Task TestUpdateForProject(
        string dependencyName,
        string oldVersion,
        string newVersion,
        string projectContents,
        string expectedProjectContents,
        bool isTransitive = false,
        TestFile[]? additionalFiles = null,
        TestFile[]? additionalFilesExpected = null,
        MockNuGetPackage[]? packages = null,
        string projectFilePath = "test-project.csproj")
        => TestUpdateForProject(
            dependencyName,
            oldVersion,
            newVersion,
            (Path: projectFilePath, Content: projectContents),
            expectedProjectContents,
            isTransitive,
            additionalFiles,
            additionalFilesExpected,
            packages);

    protected static async Task TestUpdateForProject(
        string dependencyName,
        string oldVersion,
        string newVersion,
        TestFile projectFile,
        string expectedProjectContents,
        bool isTransitive = false,
        TestFile[]? additionalFiles = null,
        TestFile[]? additionalFilesExpected = null,
        MockNuGetPackage[]? packages = null)
    {
        additionalFiles ??= [];
        additionalFilesExpected ??= [];

        var placeFilesInSrc = packages is not null;

        var projectFilePath = projectFile.Path;
        var testFiles = new[] { projectFile }.Concat(additionalFiles).ToArray();
        if (placeFilesInSrc)
        {
            testFiles = testFiles.Select(f => ($"src/{f.Path}", f.Content)).ToArray();
        }

        var actualResult = await RunUpdate(testFiles, async temporaryDirectory =>
        {
            await MockNuGetPackagesInDirectory(packages, temporaryDirectory);

            // run update
            var worker = new UpdaterWorker(new Logger(verbose: true));
            var projectPath = placeFilesInSrc ? $"src/{projectFilePath}" : projectFilePath;
            await worker.RunAsync(temporaryDirectory, projectPath, dependencyName, oldVersion, newVersion, isTransitive);
        });

        var expectedResult = additionalFilesExpected.Prepend((projectFilePath, expectedProjectContents)).ToArray();
        if (placeFilesInSrc)
        {
            expectedResult = expectedResult.Select(er => ($"src/{er.Item1}", er.Item2)).ToArray();
        }

        AssertContainsFiles(expectedResult, actualResult);
    }

    protected static Task TestNoChangeforSolution(
        string dependencyName,
        string oldVersion,
        string newVersion,
        TestFile[] projectFiles,
        bool isTransitive = false,
        TestFile[]? additionalFiles = null,
        MockNuGetPackage[]? packages = null)
        => TestUpdateForSolution(
            dependencyName,
            oldVersion,
            newVersion,
            projectFiles,
            projectFilesExpected: projectFiles,
            isTransitive,
            additionalFiles,
            additionalFilesExpected: additionalFiles,
            packages: packages);

    protected static async Task TestUpdateForSolution(
        string dependencyName,
        string oldVersion,
        string newVersion,
        TestFile[] projectFiles,
        TestFile[] projectFilesExpected,
        bool isTransitive = false,
        TestFile[]? additionalFiles = null,
        TestFile[]? additionalFilesExpected = null,
        MockNuGetPackage[]? packages = null)
    {
        additionalFiles ??= [];
        additionalFilesExpected ??= [];

        var testProjects = projectFiles.Select(file => new TestProject(file.Path, file.Content, Guid.NewGuid())).ToArray();
        var projectDeclarations = testProjects.Select(project => $$"""
            Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "{{Path.GetFileNameWithoutExtension(project.Path)}}", "{{project.Path}}", "{{project.ProjectId}}"
            EndProject
            """);
        var debugConfiguration = testProjects.Select(project => $$"""
                {{project.ProjectId}}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
                {{project.ProjectId}}.Debug|Any CPU.Build.0 = Debug|Any CPU
                {{project.ProjectId}}..Release|Any CPU.ActiveCfg = Release|Any CPU
                {{project.ProjectId}}..Release|Any CPU.Build.0 = Release|Any CPU
            """);

        var slnName = "test-solution.sln";
        var slnContent = $$"""
            Microsoft Visual Studio Solution File, Format Version 12.00
            # Visual Studio 14
            VisualStudioVersion = 14.0.22705.0
            MinimumVisualStudioVersion = 10.0.40219.1
            {{string.Join(Environment.NewLine, projectDeclarations)}}
            Global
              GlobalSection(SolutionConfigurationPlatforms) = preSolution
                Debug|Any CPU = Debug|Any CPU
                Release|Any CPU = Release|Any CPU
              EndGlobalSection
              GlobalSection(ProjectConfigurationPlatforms) = postSolution
            {{string.Join(Environment.NewLine, debugConfiguration)}}
              EndGlobalSection
              GlobalSection(SolutionProperties) = preSolution
                HideSolutionNode = FALSE
              EndGlobalSection
            EndGlobal
            """;
        var testFiles = new[] { (slnName, slnContent) }.Concat(projectFiles).Concat(additionalFiles).ToArray();

        var actualResult = await RunUpdate(testFiles, async temporaryDirectory =>
        {
            await MockNuGetPackagesInDirectory(packages, temporaryDirectory);

            var slnPath = Path.Combine(temporaryDirectory, slnName);
            var worker = new UpdaterWorker(new Logger(verbose: true));
            await worker.RunAsync(temporaryDirectory, slnPath, dependencyName, oldVersion, newVersion, isTransitive);
        });

        var expectedResult = projectFilesExpected.Concat(additionalFilesExpected).ToArray();

        AssertContainsFiles(expectedResult, actualResult);
    }

    public static async Task MockNuGetPackagesInDirectory(MockNuGetPackage[]? packages, string temporaryDirectory)
    {
        if (packages is not null)
        {
            string localFeedPath = Path.Join(temporaryDirectory, "local-feed");
            Directory.CreateDirectory(localFeedPath);
            MockNuGetPackage[] allPackages = packages.Concat(MockNuGetPackage.CommonPackages).ToArray();

            // write all packages to disk
            foreach (MockNuGetPackage package in allPackages)
            {
                package.WriteToDirectory(localFeedPath);
            }

            // override various nuget locations
            foreach (var envName in new[] { "NUGET_PACKAGES", "NUGET_HTTP_CACHE_PATH", "NUGET_SCRATCH", "NUGET_PLUGINS_CACHE_PATH" })
            {
                string dir = Path.Join(temporaryDirectory, envName);
                Directory.CreateDirectory(dir);
                Environment.SetEnvironmentVariable(envName, dir);
            }

            // ensure only the test feed is used
            string relativeLocalFeedPath = Path.GetRelativePath(temporaryDirectory, localFeedPath);
            await File.WriteAllTextAsync(Path.Join(temporaryDirectory, "NuGet.Config"), $"""
                <?xml version="1.0" encoding="utf-8"?>
                <configuration>
                  <packageSources>
                    <clear />
                    <add key="local-feed" value="{relativeLocalFeedPath}" />
                  </packageSources>
                </configuration>
                """
            );
        }
    }

    protected static async Task<TestFile[]> RunUpdate(TestFile[] files, Func<string, Task> action)
    {
        // write initial files
        using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync(files);

        // run update
        await action(temporaryDirectory.DirectoryPath);

        // gather results
        var filePaths = files.Select(f => f.Path).ToHashSet();
        return await temporaryDirectory.ReadFileContentsAsync(filePaths);
    }

    protected static void AssertEqualFiles(TestFile[] expected, TestFile[] actual)
    {
        Assert.Equal(expected.Length, actual.Length);
        AssertContainsFiles(expected, actual);
    }

    protected static void AssertContainsFiles(TestFile[] expected, TestFile[] actual)
    {
        var actualContents = actual.ToDictionary(pair => pair.Path, pair => pair.Content);
        foreach (var expectedPair in expected)
        {
            var actualContent = actualContents[expectedPair.Path];
            var expectedContent = expectedPair.Content;
            Assert.Equal(expectedContent.Replace("\r", ""), actualContent.Replace("\r", "")); // normalize line endings
        }
    }
}
