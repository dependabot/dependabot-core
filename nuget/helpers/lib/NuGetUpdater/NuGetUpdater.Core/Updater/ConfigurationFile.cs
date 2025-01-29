namespace NuGetUpdater.Core;

public record ConfigurationFile(string Path, string Content, bool ShouldAddToProject);
