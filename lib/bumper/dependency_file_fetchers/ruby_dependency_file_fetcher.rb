require "bumper/dependency_file"
require "bumper/workers"
require "github"

module DependencyFileFetchers
  class RubyDependencyFileFetcher
    def self.run(repos)
      repos.each do |repo|
        file_fetcher = new(repo)
        parse_files(repo, [file_fetcher.gemfile, file_fetcher.gemfile_lock])
      end
    rescue => error
      Raven.capture_exception(error)
      raise
    end

    def self.parse_files(repo, files)
      dependency_files = files.map do |file|
        { "name" => file.name, "content" => file.content }
      end

      Workers::DependencyFileParser.perform_async(
        "repo" => {
          "name" => repo,
          "language" => "ruby"
        },
        "dependency_files" => dependency_files
      )
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
