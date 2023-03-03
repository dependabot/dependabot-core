# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "sorbet-runtime"

module Dependabot
  module Shared
    class SharedFileParser < Dependabot::FileParsers::Base
      extend T::Sig
      extend T::Helpers

      abstract!

      require "dependabot/file_parsers/base/dependency_set"

      # Details of Docker regular expressions is at
      # https://github.com/docker/distribution/blob/master/reference/regexp.go
      DOMAIN_COMPONENT = /(?:[[:alnum:]]|[[:alnum:]][[[:alnum:]]-]*[[:alnum:]])/
      DOMAIN = /(?:#{DOMAIN_COMPONENT}(?:\.#{DOMAIN_COMPONENT})+)/
      REGISTRY = /(?<registry>#{DOMAIN}(?::\d+)?)/

      NAME_COMPONENT = /(?:[a-z\d]+(?:(?:[._]|__|[-]*)[a-z\d]+)*)/
      IMAGE = %r{(?<image>#{NAME_COMPONENT}(?:/#{NAME_COMPONENT})*)}

      TAG = /:(?<tag>[\w][\w.-]{0,127})/
      DIGEST = /@(?<digest>[^\s]+)/
      NAME = /\s+AS\s+(?<name>[\w-]+)/

      protected

      sig { params(parsed_line: T::Hash[String, T.nilable(String)]).returns(T.nilable(String)) }
      def version_from(parsed_line)
        parsed_line.fetch("tag") || parsed_line.fetch("digest")
      end

      sig { params(parsed_line: T::Hash[String, T.nilable(String)]).returns(T::Hash[String, T.nilable(String)]) }
      def source_from(parsed_line)
        source = {}

        source[:registry] = parsed_line.fetch("registry") if parsed_line.fetch("registry")
        source[:tag] = parsed_line.fetch("tag") if parsed_line.fetch("tag")
        source[:digest] = parsed_line.fetch("digest") if parsed_line.fetch("digest")

        source
      end

      sig do
        params(file: Dependabot::DependencyFile, details: T::Hash[String, T.nilable(String)],
               version: String).returns(Dependabot::Dependency)
      end
      def build_dependency(file, details, version)
        Dependency.new(
          name: T.must(details.fetch("image")),
          version: version,
          package_manager: package_manager,
          requirements: [
            requirement: nil,
            groups: [],
            file: file.name,
            source: source_from(details)
          ]
        )
      end

      private

      sig { override.void }
      def check_required_files; end

      sig { abstract.returns(String) }
      def package_manager; end

      sig { abstract.returns(String) }
      def file_type; end
    end
  end
end
