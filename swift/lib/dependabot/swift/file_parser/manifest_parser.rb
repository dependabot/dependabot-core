# typed: strong
# frozen_string_literal: true

require "dependabot/file_parsers/base"
require "dependabot/dependency_requirement"
require "dependabot/swift/native_requirement"

module Dependabot
  module Swift
    class FileParser < Dependabot::FileParsers::Base
      class ManifestParser
        extend T::Sig
        extend T::Helpers

        # An optional `name:` label may precede the `url:` argument.
        NAME_ARGUMENT = /(?:name:\s+"[^"]+",\s*)?/

        # The `url:` argument identifies the dependency's source.
        URL_ARGUMENT = /url:\s+"(?<url>[^"]+)",\s*/

        # The version requirement (e.g. `from: "1.0.0"`, `.upToNextMajor(from: "1.0.0")`, a range).
        REQUIREMENT_ARGUMENT = /(?<requirement>#{NativeRequirement::REGEXP})/

        # A single additional labeled argument (e.g. `traits: []`) whose value may be an array, a
        # string, or a bare token. The leading comma is optional so the final argument matches too.
        TRAILING_ARGUMENT = /\s*,?\s*\w+\s*:\s*(?:\[[^\]]*\]|"[^"]*"|[^\s,)]+)/

        # After the requirement there may be any number of trailing arguments (which can span onto
        # following lines) before the closing `)`, optionally followed by a trailing comma.
        TRAILING_ARGUMENTS = /(?:#{TRAILING_ARGUMENT})*\s*,?\s*/

        DEPENDENCY =
          /(?<declaration>\.package\(\s*
            #{NAME_ARGUMENT}#{URL_ARGUMENT}#{REQUIREMENT_ARGUMENT}#{TRAILING_ARGUMENTS}
           \))/x

        sig do
          params(
            manifest: Dependabot::DependencyFile,
            requirement: Dependabot::DependencyRequirement
          ).void
        end
        def initialize(manifest, requirement:)
          @manifest = manifest
          @requirement = requirement
        end

        sig { returns(T::Array[T::Hash[Symbol, Object]]) }
        def requirements
          found = manifest.content&.scan(DEPENDENCY)&.find do |_declaration, url, _requirement|
            SharedHelpers.scp_to_standard(url.to_s) == requirement.source_string("url")
          end

          return [] unless found

          declaration = T.cast(found, T::Array[String]).first
          requirement = NativeRequirement.new(T.must(T.cast(found, T::Array[String]).last))

          [
            {
              requirement: requirement.to_s,
              groups: ["dependencies"],
              file: manifest.name,
              source: T.must(self.requirement.source_hash),
              metadata: { declaration_string: declaration, requirement_string: requirement.declaration }
            }
          ]
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :manifest

        sig { returns(Dependabot::DependencyRequirement) }
        attr_reader :requirement
      end
    end
  end
end
