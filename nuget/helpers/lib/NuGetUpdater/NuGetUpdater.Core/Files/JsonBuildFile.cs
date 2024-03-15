using System.Text.Json;
using System.Text.Json.Nodes;

using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core;

internal abstract class JsonBuildFile : BuildFile<string>
{
    protected Lazy<JsonNode?> Node;
    private readonly Logger logger;

    public JsonBuildFile(string repoRootPath, string path, string contents, Logger logger)
        : base(repoRootPath, path, contents)
    {
        Node = new Lazy<JsonNode?>(() => null);
        this.logger = logger;
        ResetNode();
    }

    protected override string GetContentsString(string _contents) => Contents;

    public void UpdateProperty(string[] propertyPath, string newValue)
    {
        var updatedContents = JsonHelper.UpdateJsonProperty(Contents, propertyPath, newValue, StringComparison.OrdinalIgnoreCase);
        Update(updatedContents);
        ResetNode();
    }

    private void ResetNode()
    {
        Node = new Lazy<JsonNode?>(() =>
        {
            try
            {
                return JsonHelper.ParseNode(Contents);
            }
            catch (JsonException ex)
            {
                // We can't police that people have legal JSON files.
                // If they don't, we just return null.
                logger.Log($"Failed to parse JSON file: {RelativePath}, got {ex}");
                return null;
            }
        });
    }
}
