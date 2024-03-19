using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

using Xunit;

using TestFile = (string Path, string Content);
using TestProject = (string Path, string Content, System.Guid ProjectId);

namespace NuGetUpdater.Core.Test.Update;

public abstract class UpdateWorkerTestBase
{
    protected static Task TestNoChange(
        string dependencyName,
        string oldVersion,
        string newVersion,
        bool useSolution,
        string projectContents,
        bool isTransitive = false,
        (string Path, string Content)[]? additionalFiles = null,
        string projectFilePath = "test-project.csproj")
    {
        return useSolution
            ? TestNoChangeforSolution(dependencyName, oldVersion, newVersion, projectFiles: [(projectFilePath, projectContents)], isTransitive, additionalFiles)
            : TestNoChangeforProject(dependencyName, oldVersion, newVersion, projectContents, isTransitive, additionalFiles, projectFilePath);
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
        string projectFilePath = "test-project.csproj")
    {
        return useSolution
            ? TestUpdateForSolution(dependencyName, oldVersion, newVersion, projectFiles: [(projectFilePath, projectContents)], projectFilesExpected: [(projectFilePath, expectedProjectContents)], isTransitive, additionalFiles, additionalFilesExpected)
            : TestUpdateForProject(dependencyName, oldVersion, newVersion, projectFile: (projectFilePath, projectContents), expectedProjectContents, isTransitive, additionalFiles, additionalFilesExpected);
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
        TestFile[]? additionalFilesExpected = null)
    {
        return useSolution
            ? TestUpdateForSolution(dependencyName, oldVersion, newVersion, projectFiles: [projectFile], projectFilesExpected: [(projectFile.Path, expectedProjectContents)], isTransitive, additionalFiles, additionalFilesExpected)
            : TestUpdateForProject(dependencyName, oldVersion, newVersion, projectFile, expectedProjectContents, isTransitive, additionalFiles, additionalFilesExpected);
    }

    protected static Task TestNoChangeforProject(
        string dependencyName,
        string oldVersion,
        string newVersion,
        string projectContents,
        bool isTransitive = false,
        (string Path, string Content)[]? additionalFiles = null,
        string projectFilePath = "test-project.csproj")
        => TestUpdateForProject(
            dependencyName,
            oldVersion,
            newVersion,
            (projectFilePath, projectContents),
            expectedProjectContents: projectContents,
            isTransitive,
            additionalFiles,
            additionalFilesExpected: additionalFiles);

    protected static Task TestUpdateForProject(
        string dependencyName,
        string oldVersion,
        string newVersion,
        string projectContents,
        string expectedProjectContents,
        bool isTransitive = false,
        TestFile[]? additionalFiles = null,
        TestFile[]? additionalFilesExpected = null,
        string projectFilePath = "test-project.csproj")
        => TestUpdateForProject(
            dependencyName,
            oldVersion,
            newVersion,
            (Path: projectFilePath, Content: projectContents),
            expectedProjectContents,
            isTransitive,
            additionalFiles,
            additionalFilesExpected);

    protected static async Task TestUpdateForProject(
        string dependencyName,
        string oldVersion,
        string newVersion,
        TestFile projectFile,
        string expectedProjectContents,
        bool isTransitive = false,
        TestFile[]? additionalFiles = null,
        TestFile[]? additionalFilesExpected = null)
    {
        additionalFiles ??= [];
        additionalFilesExpected ??= [];

        var projectFilePath = projectFile.Path;
        var testFiles = new[] { projectFile }.Concat(additionalFiles).ToArray();

        var actualResult = await RunUpdate(testFiles, async temporaryDirectory =>
        {
            var worker = new UpdaterWorker(new Logger(verbose: true));
            await worker.RunAsync(temporaryDirectory, projectFilePath, dependencyName, oldVersion, newVersion, isTransitive);
        });

        var expectedResult = additionalFilesExpected.Prepend((projectFilePath, expectedProjectContents)).ToArray();

        AssertContainsFiles(expectedResult, actualResult);
    }

    protected static Task TestNoChangeforSolution(
        string dependencyName,
        string oldVersion,
        string newVersion,
        TestFile[] projectFiles,
        bool isTransitive = false,
        TestFile[]? additionalFiles = null)
        => TestUpdateForSolution(
            dependencyName,
            oldVersion,
            newVersion,
            projectFiles,
            projectFilesExpected: projectFiles,
            isTransitive,
            additionalFiles,
            additionalFilesExpected: additionalFiles);

    protected static async Task TestUpdateForSolution(
        string dependencyName,
        string oldVersion,
        string newVersion,
        TestFile[] projectFiles,
        TestFile[] projectFilesExpected,
        bool isTransitive = false,
        TestFile[]? additionalFiles = null,
        TestFile[]? additionalFilesExpected = null)
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
            var slnPath = Path.Combine(temporaryDirectory, slnName);
            var worker = new UpdaterWorker(new Logger(verbose: true));
            await worker.RunAsync(temporaryDirectory, slnPath, dependencyName, oldVersion, newVersion, isTransitive);
        });

        var expectedResult = projectFilesExpected.Concat(additionalFilesExpected).ToArray();

        AssertContainsFiles(expectedResult, actualResult);
    }

    protected static async Task<(string Path, string Content)[]> RunUpdate((string Path, string Content)[] files, Func<string, Task> action)
    {
        // write initial files
        using var tempDir = new TemporaryDirectory();
        foreach (var file in files)
        {
            var localPath = file.Path.StartsWith('/') ? file.Path[1..] : file.Path; // remove path rooting character
            var filePath = Path.Combine(tempDir.DirectoryPath, localPath);
            var directoryPath = Path.GetDirectoryName(filePath);
            Directory.CreateDirectory(directoryPath!);
            await File.WriteAllTextAsync(filePath, file.Content);
        }

        // run update
        await action(tempDir.DirectoryPath);

        // gather results
        var expectedFiles = new HashSet<string>(files.Select(f => f.Path));
        var result = new List<(string Path, string Content)>();
        foreach (var file in Directory.GetFiles(tempDir.DirectoryPath, "*.*", SearchOption.AllDirectories))
        {
            var localPath = file.StartsWith(tempDir.DirectoryPath)
                ? file[tempDir.DirectoryPath.Length..]
                : file; // how did this happen?
            localPath = localPath.NormalizePathToUnix();
            if (localPath.StartsWith('/'))
            {
                localPath = localPath[1..];
            }

            if (expectedFiles.Contains(localPath))
            {
                var content = await File.ReadAllTextAsync(file);
                result.Add((localPath, content));
            }
        }

        return result.ToArray();
    }

    protected static void AssertEqualFiles((string Path, string Content)[] expected, (string Path, string Content)[] actual)
    {
        Assert.Equal(expected.Length, actual.Length);
        AssertContainsFiles(expected, actual);
    }

    protected static void AssertContainsFiles((string Path, string Content)[] expected, (string Path, string Content)[] actual)
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
