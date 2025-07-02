using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace NuGetUpdater.Core.Updater.FileWriters;

public interface IDependencySolver
{
    Task<ImmutableArray<Dependency>?> SolveAsync(ImmutableArray<Dependency> existingTopLevelDependencies, ImmutableArray<Dependency> desiredDependencies, string targetFramework);
}
