require "bumper/dependency_file"
require "bumper/workers"
require "github"

module DependencyFileFetchers
  class RubyDependencyFileFetcher
    attr_reader :repo

    def initialize(repo)
      @repo = repo
    end

    def files
      [gemfile, gemfile_lock]
    end

    private

    def gemfile
      DependencyFile.new(name: "Gemfile", content: gemfile_content)
    end

    def gemfile_lock
      DependencyFile.new(name: "Gemfile.lock", content: gemfile_lock_content)
    end

    def gemfile_content
      @gemfile_content ||=
        Base64.decode64(Github.client.contents(repo, path: "Gemfile").content)
    end

    def gemfile_lock_content
      @gemfile_lock_content ||=
        Base64.decode64(
          Github.client.contents(repo, path: "Gemfile.lock").content
        )
    end
  end
end
