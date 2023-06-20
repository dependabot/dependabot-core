using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

using Microsoft.Build.Construction;
using Microsoft.Build.Locator;

namespace NuGetUpdater.Core
{
    internal class MSBuildHelper
    {
        internal static IEnumerable<string> GetAllProjectPaths(string projFilePath)
        {
            try
            {
                // Ensure MSBuild types are registered before calling a method that loads the types
                if (!MSBuildLocator.IsRegistered)
                {
                    var defaultInstance = MSBuildLocator.QueryVisualStudioInstances().FirstOrDefault();
                    MSBuildLocator.RegisterInstance(defaultInstance);
                }

                return GetAllProjectPathsImpl(projFilePath);
            }
            catch (Exception)
            {
                return Enumerable.Empty<string>();
            }
        }

        private static IEnumerable<string> GetAllProjectPathsImpl(string projFilePath)
        {
            var projectStack = new Stack<(string folderPath, ProjectRootElement)>();
            var projectRootElement = ProjectRootElement.Open(projFilePath);

            projectStack.Push((Path.GetFullPath(Path.GetDirectoryName(projFilePath)!), projectRootElement));

            while (projectStack.Count > 0)
            {
                var (folderPath, tmpProject) = projectStack.Pop();
                foreach (var projectReference in tmpProject.Items.Where(static x => x.ItemType == "ProjectReference"))
                {
                    if (projectReference.Include is not { } projectPath)
                    {
                        continue;
                    }

                    projectPath = GetFullPathFromRelative(folderPath, projectPath);

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

            static string GetFullPathFromRelative(string rootPath, string relativePath)
                => Path.GetFullPath(Path.Combine(rootPath, relativePath));
        }
    }
}