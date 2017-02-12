require "sidekiq"
require "./app/boot"
require "./app/dependency_file"
require "./app/dependency_file_fetchers/ruby"
require "./app/dependency_file_fetchers/node"
require "./app/dependency_file_fetchers/python"
require "./app/dependency_file_parsers/ruby"
require "./app/dependency_file_parsers/node"
require "./app/dependency_file_parsers/python"

$stdout.sync = true

module Workers
  class DependencyFileFetcher
    include Sidekiq::Worker

    sidekiq_options queue: "bump-repos_to_fetch_files_for", retry: 4

    sidekiq_retry_in { |count| [60, 300, 3_600, 36_000][count] }

    def perform(body)
      @body = body

      file_fetcher = file_fetcher_for(repo.language).new(repo.name)

      parser = parser_for(repo.language)

      dependencies = parser.new(dependency_files: file_fetcher.files).parse

      dependencies.each do |dependency|
        Workers::DependencyUpdater.perform_async(
          "repo" => repo.to_h.merge("commit" => file_fetcher.commit),
          "dependency_files" => file_fetcher.files.map(&:to_h),
          "dependency" => {
            "name" => dependency.name,
            "version" => dependency.version
          }
        )
      end

    rescue => error
      Raven.capture_exception(error, extra: { body: body })
      raise
    end

    private

    def repo
      @repo ||= Repo.new(
        name: @body["repo"]["name"],
        language: @body["repo"]["language"],
        commit: nil
      )
    end

    def file_fetcher_for(language)
      case language
      when "ruby" then DependencyFileFetchers::Ruby
      when "node" then DependencyFileFetchers::Node
      when "python" then DependencyFileFetchers::Python
      else raise "Invalid language #{language}"
      end
    end

    def parser_for(language)
      case language
      when "ruby" then ::DependencyFileParsers::Ruby
      when "node" then ::DependencyFileParsers::Node
      when "python" then ::DependencyFileParsers::Python
      else raise "Invalid language #{language}"
      end
    end
  end
end
