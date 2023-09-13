# typed: true
# frozen_string_literal: true

require "dependabot/file_parsers/base"
require "dependabot/swift/native_requirement"

module Dependabot
  module Swift
    class FileParser < Dependabot::FileParsers::Base
      class ManifestParser
        DEPENDENCY =
          /(?<declaration>\.package\(\s*
            (?:name:\s+"[^"]+",\s*)?url:\s+"(?<url>[^"]+)",\s*(?<requirement>#{NativeRequirement::REGEXP})\s*
           \))/x

        def initialize(manifest, source:)
          @manifest = manifest
          @source = source
        end

        def requirements
          found = manifest.content.scan(DEPENDENCY).find do |_declaration, url, _requirement|
            SharedHelpers.scp_to_standard(url) == source[:url]
          end

          return [] unless found

          declaration = found.first
          requirement = NativeRequirement.new(found.last)

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

        attr_reader :manifest, :source
      end
    end
  end
end
