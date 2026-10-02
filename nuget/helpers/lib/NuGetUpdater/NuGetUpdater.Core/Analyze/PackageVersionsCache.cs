using NuGet.Configuration;
using NuGet.Versioning;

namespace NuGetUpdater.Core.Analyze;

internal sealed class PackageVersionsCache
{
    private readonly Dictionary<CacheKey, Task<PackageVersions>> _cache = [];
    private readonly object _cacheLock = new();

    public async Task<PackageVersions> GetVersionsAsync(
        string currentDirectory,
        PackageSource source,
        string packageId,
        bool includePrerelease,
        bool includeUnlisted,
        Func<CancellationToken, Task<IEnumerable<NuGetVersion>>> getVersionsAsync,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var key = new CacheKey(
            Path.TrimEndingDirectorySeparator(Path.GetFullPath(currentDirectory)),
            source.Name,
            source.Source,
            packageId.ToLowerInvariant(),
            includePrerelease,
            includeUnlisted);

        Task<PackageVersions> versionsTask;
        var createdLoad = false;
        lock (_cacheLock)
        {
            if (_cache.TryGetValue(key, out var cachedTask))
            {
                versionsTask = cachedTask;
            }
            else
            {
                versionsTask = LoadVersionsAsync(getVersionsAsync, cancellationToken);
                _cache.Add(key, versionsTask);
                createdLoad = true;
            }
        }

        try
        {
            return await versionsTask.WaitAsync(cancellationToken);
        }
        catch
        {
            if (!versionsTask.IsCompletedSuccessfully &&
                (createdLoad || versionsTask.IsCanceled || versionsTask.IsFaulted))
            {
                lock (_cacheLock)
                {
                    if (_cache.TryGetValue(key, out var cachedTask) && ReferenceEquals(cachedTask, versionsTask))
                    {
                        _cache.Remove(key);
                    }
                }
            }

            throw;
        }
    }

    private static async Task<PackageVersions> LoadVersionsAsync(
        Func<CancellationToken, Task<IEnumerable<NuGetVersion>>> getVersionsAsync,
        CancellationToken cancellationToken)
    {
        var versions = await getVersionsAsync(cancellationToken);
        return new PackageVersions(versions.ToHashSet());
    }

    private sealed record CacheKey(
        string CurrentDirectory,
        string SourceName,
        string SourceUrl,
        string PackageId,
        bool IncludePrerelease,
        bool IncludeUnlisted);
}

internal sealed class PackageVersions(HashSet<NuGetVersion> items)
{
    public int Count => items.Count;
    public IEnumerable<NuGetVersion> Items => items;

    public bool Contains(NuGetVersion version) => items.Contains(version);
}
