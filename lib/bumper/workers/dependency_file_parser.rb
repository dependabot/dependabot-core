require "bumper/workers"
require "bumper/dependency_file_parsers/ruby_dependency_file_parser"

class Workers::DependencyFileParser
  include Shoryuken::Worker

  shoryuken_options queue: "bump-dependency_files", body_parser: :json

  def perform(sqs_message, body)
    parser = parser_for(body["language"])
    dependencies = parser.new(body["file"]).parse

    # TODO remove this - it's just here to test that this actually does
    #      something when we deploy it to ECS
    deps_str = Time.now.to_s + ' -- ' + dependencies.map(&:name).join(", ")
    `curl -s -d '#{deps_str}' http://requestb.in/za3prvza`

    sqs_message.delete
  end

  private

  def parser_for(language)
    case language
    when "ruby" then DependencyFileParsers::RubyDependencyFileParser
    else raise "Invalid language #{language}"
    end
  end
end
