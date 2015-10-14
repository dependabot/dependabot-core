require "shoryuken"
require "./app/boot"
require "./app/dependency_file"
require "./app/dependency_file_parsers/ruby_dependency_file_parser"
require "./app/dependency_file_parsers/node_dependency_file_parser"

$stdout.sync = true

module Workers
  class DependencyFileParser
    include Shoryuken::Worker

    shoryuken_options(
      queue: "bump-dependency_files_to_parse",
      body_parser: :json,
      auto_delete: true
    )

    def perform(_sqs_message, body)
      parser = parser_for(body["repo"]["language"])
      dependency_files = body["dependency_files"].map do |file|
        DependencyFile.new(name: file["name"], content: file["content"])
      end
      dependencies = parser.new(dependency_files: dependency_files).parse

      dependencies.each do |dependency|
        check_for_dependency_update(
          body["repo"],
          body["dependency_files"],
          dependency
        )
      end
    rescue => error
      Raven.capture_exception(error, extra: { body: body })
      raise
    end

    private

    def check_for_dependency_update(repo, dependency_files, dependency)
      Workers::UpdateChecker.perform_async(
        "repo" => repo,
        "dependency_files" => dependency_files,
        "dependency" => {
          "name" => dependency.name,
          "version" => dependency.version
        }
      )
    end

    def parser_for(language)
      case language
      when "ruby" then DependencyFileParsers::RubyDependencyFileParser
      when "node" then DependencyFileParsers::NodeDependencyFileParser
      else raise "Invalid language #{language}"
      end
    end
  end
end
