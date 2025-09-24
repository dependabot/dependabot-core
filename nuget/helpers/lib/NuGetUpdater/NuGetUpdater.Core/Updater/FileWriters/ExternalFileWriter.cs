using System.Collections.Immutable;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Updater.FileWriters;

public class ExternalFileWriter : IFileWriter
{
    private static readonly HttpClient HttpClient = new() { Timeout = TimeSpan.FromMinutes(5) };

    private readonly string _url;
    private readonly ILogger _logger;

    public ExternalFileWriter(string url, ILogger logger)
    {
        _url = url;
        _logger = logger;
    }

    public async Task<bool> UpdatePackageVersionsAsync(DirectoryInfo repoContentsPath, ImmutableArray<string> relativeFilePaths, ImmutableArray<Dependency> originalDependencies, ImmutableArray<Dependency> requiredPackageVersions, bool addPackageReferenceElementForPinnedPackages)
    {
        // build request payload
        var oldPackageVersions = originalDependencies.ToDictionary(d => d.Name, d => d.Version ?? string.Empty);
        var packagesToUpdate = requiredPackageVersions
            .Where(d => d.Version is not null)
            .Where(d => oldPackageVersions.ContainsKey(d.Name) && oldPackageVersions[d.Name] != d.Version)
            .Select(d => new FileEditPackageInfo() { Name = d.Name, OldVersion = oldPackageVersions[d.Name], NewVersion = d.Version! }).ToImmutableArray();
        var filesTasks = relativeFilePaths
            .Select(async path =>
            {
                var content = await File.ReadAllTextAsync(Path.Join(repoContentsPath.FullName, path));
                return new FileEditFile()
                {
                    Path = path,
                    Content = content,
                };
            });
        var files = (await Task.WhenAll(filesTasks))
            .ToImmutableArray();
        var fileEditRequest = new FileEditRequest()
        {
            PackagesToUpdate = packagesToUpdate,
            Files = files,
        };

        // make request
        var request = SerializeRequest(fileEditRequest);
        var content = new StringContent(request, Encoding.UTF8, "application/json");

        HttpResponseMessage httpResponse;
        try
        {
            httpResponse = await HttpClient.PostAsync(_url, content);
        }
        catch (Exception ex)
        {
            _logger.Error($"Failed to send request to external file writer: {ex}");
            return false;
        }

        // report results
        if (!httpResponse.IsSuccessStatusCode)
        {
            return false;
        }

        var jsonResponse = await httpResponse.Content.ReadAsStringAsync();
        FileEditResponse? response;
        try
        {
            response = DeserializeResponse(jsonResponse);
        }
        catch (Exception ex)
        {
            _logger.Error($"Failed to deserialize response from external file writer: {ex}");
            return false;
        }

        if (response is null)
        {
            _logger.Error("Received null response from external file writer.");
            return false;
        }

        if (!response.Success)
        {
            _logger.Info($"External file writer unable to make requested edits.");
            return false;
        }

        // edit was successful, write the files back to disk
        foreach (var file in response.Files)
        {
            var fullPath = Path.Join(repoContentsPath.FullName, file.Path);
            if (!File.Exists(fullPath))
            {
                _logger.Warn($"File {file.Path} does not exist in the repository. Skipping write.");
                continue;
            }

            await File.WriteAllTextAsync(fullPath, file.Content);
        }

        return true;
    }

    public static string SerializeRequest(FileEditRequest request)
    {
        var json = JsonSerializer.Serialize(request);
        return json;
    }

    public static string SerializeResponse(FileEditResponse response)
    {
        var json = JsonSerializer.Serialize(response);
        return json;
    }

    public static FileEditRequest? DeserializeRequest(string json)
    {
        var request = JsonSerializer.Deserialize<FileEditRequest>(json);
        return request;
    }

    public static FileEditResponse? DeserializeResponse(string json)
    {
        var response = JsonSerializer.Deserialize<FileEditResponse>(json);
        return response;
    }
}

public record FileEditFile
{
    [JsonPropertyName("path")]
    public required string Path { get; init; }

    [JsonPropertyName("content")]
    public required string Content { get; init; }
}

public record FileEditPackageInfo
{
    [JsonPropertyName("name")]
    public required string Name { get; init; }

    [JsonPropertyName("oldVersion")]
    public required string OldVersion { get; init; }

    [JsonPropertyName("newVersion")]
    public required string NewVersion { get; init; }
}

public record FileEditRequest
{
    [JsonPropertyName("packagesToUpdate")]
    public required ImmutableArray<FileEditPackageInfo> PackagesToUpdate { get; init; }

    [JsonPropertyName("files")]
    public required ImmutableArray<FileEditFile> Files { get; init; }
}

public record FileEditResponse
{
    [JsonPropertyName("success")]
    public required bool Success { get; init; }

    [JsonPropertyName("files")]
    public required ImmutableArray<FileEditFile> Files { get; init; }
}
