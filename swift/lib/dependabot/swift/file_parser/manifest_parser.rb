# typed: strong
# frozen_string_literal: true

require "dependabot/file_parsers/base"
require "dependabot/swift/native_requirement"

module Dependabot
  module Swift
    class FileParser < Dependabot::FileParsers::Base
      class ManifestParser
        extend T::Sig
        extend T::Helpers

        DEPENDENCY =
          /(?<declaration>\.package\(\s*
            (?:name:\s+"[^"]+",\s*)?url:\s+"(?<url>[^"]+)",\s*(?<requirement>#{NativeRequirement::REGEXP})\s*
           \))/x

        sig do
          params(
            manifest: Dependabot::DependencyFile,
            source: T::Hash[Symbol, String]
          ).void
        end
        def initialize(manifest, source:)
          @manifest = manifest
          @source = source
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def requirements
          found = manifest.content&.scan(DEPENDENCY)&.find do |_declaration, url, _requirement|
            SharedHelpers.scp_to_standard(url.to_s) == source[:url]
          end

          return [] unless found

          declaration = T.cast(found, T::Array[String]).first
          requirement = NativeRequirement.new(T.must(T.cast(found, T::Array[String]).last))

          [
            {
              requirement: requirement.to_s,
              groups: ["dependencies"],
              file: manifest.name,
              source: source,
              metadata: { declaration_string: declaration, requirement_string: requirement.declaration }
            }
          ]
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :manifest

        sig { returns(T::Hash[Symbol, String]) }
        attr_reader :source
      end
    end
  end
end
