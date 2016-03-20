require "sidekiq"
require "./app/boot"
require "./app/dependency_file_fetchers/ruby"
require "./app/dependency_file_fetchers/node"
require "./app/workers/dependency_file_parser"

$stdout.sync = true

module Workers
  class DependencyFileFetcher
    include Sidekiq::Worker

    sidekiq_options queue: "bump-repos_to_fetch_files_for", retry: 4

    sidekiq_retry_in { |count| [60, 300, 3_600, 36_000][count] }

    def perform(body)
      file_fetcher =
        file_fetcher_for(body["repo"]["language"]).new(body["repo"]["name"])

      dependency_files = file_fetcher.files.map do |file|
        { "name" => file.name, "content" => file.content }
      end

      repo = body["repo"].merge("commit" => file_fetcher.commit)

      Workers::DependencyFileParser.perform_async(
        "repo" => repo,
        "dependency_files" => dependency_files
      )
    rescue => error
      Raven.capture_exception(error, extra: { body: body })
      raise
    end

    private

    def file_fetcher_for(language)
      case language
      when "ruby" then DependencyFileFetchers::Ruby
      when "node" then DependencyFileFetchers::Node
      else raise "Invalid language #{language}"
      end
    end
  end
end
