require "bumper/dependency_file"
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

    def gemfile_lock
      DependencyFile.new(name: "Gemfile.lock", content: gemfile_lock_content)
    end

    private

    def gemfile_content
      @gemfile_content ||=
        Base64::decode64(Github.client.contents(repo, path: "Gemfile").content)
    end

    def gemfile_lock_content
      @gemfile_lock_content ||=
        Base64::decode64(Github.client.contents(repo, path: "Gemfile.lock").content)
    end
  end
end
