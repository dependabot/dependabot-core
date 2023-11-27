using System;
using System.Text.Json.Nodes;

using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core;

internal abstract class JsonBuildFile : BuildFile<string>
{
    protected Lazy<JsonNode?> Node;

    public JsonBuildFile(string repoRootPath, string path, string contents)
        : base(repoRootPath, path, contents)
    {
        Node = new Lazy<JsonNode?>(() => null);
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
        Node = new Lazy<JsonNode?>(() => JsonHelper.ParseNode(Contents));
    }
}
