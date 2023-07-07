using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Xml.Linq;

using Microsoft.Build.Construction;
using Microsoft.Build.Locator;

namespace NuGetUpdater.Core
{
    internal static class MSBuildHelper
    {
        public static string MSBuildPath { get; private set; } = string.Empty;

        public static bool IsMSBuildRegistered => MSBuildPath.Length > 0;

        public static void RegisterMSBuild()
        {
            // Ensure MSBuild types are registered before calling a method that loads the types
            if (!IsMSBuildRegistered)
            {
                var defaultInstance = MSBuildLocator.QueryVisualStudioInstances().First();
                MSBuildPath = defaultInstance.MSBuildPath;
                MSBuildLocator.RegisterInstance(defaultInstance);
            }
        }

        public static string[] GetTargetFrameworkMonikersFromProject(string projectPath)
        {
            var projectRootElement = ProjectRootElement.Open(projectPath);
            var tfmElement = projectRootElement.Properties.FirstOrDefault(p =>
                "TargetFramework".Equals(p.Name, StringComparison.OrdinalIgnoreCase) ||
                "TargetFrameworks".Equals(p.Name, StringComparison.OrdinalIgnoreCase));
            return tfmElement is not null
                ? tfmElement.Value.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                : Array.Empty<string>();
        }

        public static IEnumerable<string> GetProjectPathsFromSolution(string solutionPath)
        {
            var solution = SolutionFile.Parse(solutionPath);
            return solution.ProjectsInOrder.Select(p => p.AbsolutePath);
        }

        public static IEnumerable<string> GetProjectPathsFromProject(string projFilePath)
        {
            var projectStack = new Stack<(string folderPath, ProjectRootElement)>();
            var projectRootElement = ProjectRootElement.Open(projFilePath);

            projectStack.Push((Path.GetFullPath(Path.GetDirectoryName(projFilePath)!), projectRootElement));

            while (projectStack.Count > 0)
            {
                var (folderPath, tmpProject) = projectStack.Pop();
                foreach (var projectReference in tmpProject.Items.Where(static x => x.ItemType == "ProjectReference" || x.ItemType == "ProjectFile"))
                {
                    if (projectReference.Include is not { } projectPath)
                    {
                        continue;
                    }

                    projectPath = PathHelper.GetFullPathFromRelative(folderPath, projectPath);

                    var projectExtension = Path.GetExtension(projectPath).ToLowerInvariant();
                    if (projectExtension == ".proj")
                    {
                        var additionalProjectRootElement = ProjectRootElement.Open(projectPath);
                        projectStack.Push((Path.GetFullPath(Path.GetDirectoryName(projectPath)!), additionalProjectRootElement));
                    }
                    else if (projectExtension == ".csproj" || projectExtension == ".vbproj" || projectExtension == ".fsproj")
                    {
                        yield return projectPath;
                    }
                }
            }
        }
    }
}