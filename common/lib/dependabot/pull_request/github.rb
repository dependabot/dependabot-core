# frozen_string_literal: true

module Dependabot
  class PullRequest
    class Github
      def initialize(client)
        @client = client
      end

      def create_tree(repo, base_commit, files)
        file_trees = files.map do |file|
          if file.type == "submodule"
            {
              path: file.path.sub(%r{^/}, ""),
              mode: "160000",
              type: "commit",
              sha: file.content
            }
          else
            content = content(repo, file)
            {
              path: (file.symlink_target ||
                file.path).sub(%r{^/}, ""),
              mode: "100644",
              type: "blob"
            }.merge(content)
          end
        end

        @client.create_tree(
          repo,
          file_trees,
          base_tree: base_commit
        )
      end

      private

      def content(repo, file)
        return { sha: nil } if file.deleted?
        return { content: file.content } unless file.binary?

        sha = @client.create_blob(repo, file.content, "base64")
        { sha: sha }
      end
    end
  end
end
