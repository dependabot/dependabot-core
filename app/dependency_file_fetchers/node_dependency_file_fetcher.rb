require "./app/dependency_file"
require "./lib/github"

module DependencyFileFetchers
  class NodeDependencyFileFetcher
    attr_reader :repo

    def initialize(repo)
      @repo = repo
    end

    def files
      [package_json, shrinkwrap]
    end

        private

    def package_json
      DependencyFile.new(name: "package.json", content: package_json_content)
    end

    def shrinkwrap
      DependencyFile.new(name: "npm-shrinkwrap.json", content: shrinkwrap_content)
    end

    def package_json_content
      @package_json_content ||=
        Base64.decode64(Github.client.contents(repo, path: "package.json").content)
    end

    def shrinkwrap_content
      @shrinkwrap_content ||=
        Base64.decode64(
          Github.client.contents(repo, path: "npm-shrinkwrap.json").content
        )
    end
  end
end
