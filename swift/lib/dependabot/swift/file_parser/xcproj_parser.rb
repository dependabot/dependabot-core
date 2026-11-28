# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/swift/file_parser"
require "dependabot/swift/native_requirement"
require "dependabot/swift/url_helpers"

module Dependabot
  module Swift
    class FileParser < Dependabot::FileParsers::Base
      # Parses remote Swift package references from a project.xcproj file,
      # the JSON project format that Xcode 27.2 and later use by default.
      #
      # Returns the same shape as PbxprojParser (including the pbxproj
      # requirement kinds such as "exactVersion"), so the rest of the Xcode
      # SwiftPM support works with either project format.
      #
      # Schema: https://github.com/apple/xcode-project-format/tree/main/Sources/Library/Schema/Packages
      class XcprojParser
        extend T::Sig

        sig { params(xcproj_file: Dependabot::DependencyFile).void }
        def initialize(xcproj_file)
          @xcproj_file = xcproj_file
        end

        sig { returns(T::Hash[String, T::Hash[Symbol, Object]]) }
        def parse
          requirements = T.let({}, T::Hash[String, T::Hash[Symbol, Object]])

          remote_packages.each do |package|
            url = package["repository"]
            version = package["version"]
            next unless url.is_a?(String) && version.is_a?(Hash)

            req_info = parse_version_constraint(version)
            next unless req_info

            normalized_url = SharedHelpers.scp_to_standard(url)
            name = UrlHelpers.normalize_name(normalized_url)

            requirements[name] = req_info.merge(
              url: normalized_url,
              file: xcproj_file.name
            )
          end

          requirements
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :xcproj_file

        sig { returns(T::Array[T::Hash[String, Object]]) }
        def remote_packages
          packages = parsed_content["packages"]
          return [] unless packages.is_a?(Array)

          packages.select { |package| package.is_a?(Hash) && package["kind"] == "remote" }
        end

        sig { returns(T::Hash[String, Object]) }
        def parsed_content
          content = xcproj_file.content
          return {} unless content

          # Xcode writes trailing commas after the last element of every
          # object and array, which strict JSON does not allow.
          parsed = T.let(JSON.parse(content, allow_trailing_comma: true), Object)
          parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError => e
          raise Dependabot::DependencyFileNotParseable.new(
            xcproj_file.name,
            "#{xcproj_file.name} is not valid JSON: #{e.message}"
          )
        end

        # The constraint object holds exactly one of these keys (or the
        # version-range-min / version-range-max pair), mirroring
        # XCSchema.SwiftPackageVersionConstraint.
        sig { params(version: T::Hash[String, Object]).returns(T.nilable(T::Hash[Symbol, Object])) }
        def parse_version_constraint(version)
          if (revision = string_value(version, "revision"))
            { requirement: nil, requirement_string: nil, kind: "revision", revision: revision }
          elsif (branch = string_value(version, "branch"))
            { requirement: nil, requirement_string: nil, kind: "branch", branch: branch }
          elsif (exact = string_value(version, "version"))
            build(kind: "exactVersion", requirement_string: "exact: \"#{exact}\"")
          elsif (minor = string_value(version, "up-to-next-minor-version"))
            build(kind: "upToNextMinorVersion", requirement_string: ".upToNextMinor(from: \"#{minor}\")")
          elsif (major = string_value(version, "up-to-next-major-version"))
            build(kind: "upToNextMajorVersion", requirement_string: "from: \"#{major}\"")
          else
            parse_version_range(version)
          end
        end

        sig { params(version: T::Hash[String, Object]).returns(T.nilable(T::Hash[Symbol, Object])) }
        def parse_version_range(version)
          range = string_value(version, "version-range")
          min_version, max_version =
            if range
              range.split("..<", 2)
            else
              [string_value(version, "version-range-min"), string_value(version, "version-range-max")]
            end
          return nil unless min_version && max_version

          build(kind: "versionRange", requirement_string: "\"#{min_version}\"..<\"#{max_version}\"")
        end

        sig { params(kind: String, requirement_string: String).returns(T::Hash[Symbol, Object]) }
        def build(kind:, requirement_string:)
          {
            requirement: parse_native_requirement(requirement_string),
            requirement_string: requirement_string,
            kind: kind
          }
        end

        sig { params(version: T::Hash[String, Object], key: String).returns(T.nilable(String)) }
        def string_value(version, key)
          value = version[key]
          value.is_a?(String) ? value : nil
        end

        # Returns nil for malformed requirements rather than raising, so a
        # single bad entry doesn't stop parsing (same as PbxprojParser).
        sig { params(requirement_string: String).returns(T.nilable(String)) }
        def parse_native_requirement(requirement_string)
          NativeRequirement.new(requirement_string).to_s
        rescue RuntimeError, Gem::Requirement::BadRequirementError
          nil
        end
      end
    end
  end
end
