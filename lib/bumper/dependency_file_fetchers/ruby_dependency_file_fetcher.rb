require "bumper/dependency_file"
require "prius"

# TODO: Move me to main app file so it's clear I happen at boot time
Prius.load(:github_token)
Prius.load(:watched_repos)

require "github"

module DependencyFileFetchers
  class RubyDependencyFileFetcher

    # TODO: I probably shouldn't live here...
    def self.run
      Prius.get(:watched_repos).split(",").each do |repo|
        file_fetcher = new(repo)
        file_fetcher.gemfile
      end
    end

    attr_reader :repo

    def initialize(repo)
      @repo = repo
    end

    def gemfile
      DependencyFile.new(name: "Gemfile", content: gemfile_content)
    end

    private

    def gemfile_content
      @gemfile_content ||=
        Base64::decode64(Github.client.contents(repo, path: "Gemfile").content)
    end
  end
end
