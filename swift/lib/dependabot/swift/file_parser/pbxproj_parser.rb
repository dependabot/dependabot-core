# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/swift/file_parser"
require "dependabot/swift/native_requirement"
require "dependabot/swift/url_helpers"

module Dependabot
  module Swift
    class FileParser < Dependabot::FileParsers::Base
      # Parses XCRemoteSwiftPackageReference entries from a project.pbxproj file
      # to extract dependency requirement constraints declared in Xcode.
      #
      # Returns a hash keyed by normalized dependency name (e.g. "github.com/owner/repo")
      # mapping to requirement metadata, so the main parser can enrich
      # Package.resolved dependencies with requirement info from the Xcode project.
      class PbxprojParser
        extend T::Sig

        # Regex to extract XCRemoteSwiftPackageReference blocks from pbxproj.
        # Uses [^}]* to match the requirement block content — this is safe because
        # Xcode requirement blocks are always flat dictionaries with no nested braces.
        PACKAGE_REF_BLOCK = T.let(
          /
            isa\s*=\s*XCRemoteSwiftPackageReference;\s*
            repositoryURL\s*=\s*"(?<url>[^"]+)";\s*
            requirement\s*=\s*\{(?<requirement>[^}]*)\};
          /mx,
          Regexp
        )

        # Patterns for extracting requirement fields
        KIND_PATTERN = T.let(/kind\s*=\s*(\w+);/, Regexp)
        VERSION_NUMBER_PATTERN = T.let(/[0-9A-Za-z.+-]+/, Regexp)
        MIN_VERSION_PATTERN = T.let(/minimumVersion\s*=\s*(#{VERSION_NUMBER_PATTERN});/, Regexp)
        MAX_VERSION_PATTERN = T.let(/maximumVersion\s*=\s*(#{VERSION_NUMBER_PATTERN});/, Regexp)
        VERSION_PATTERN = T.let(/version\s*=\s*(#{VERSION_NUMBER_PATTERN});/, Regexp)
        BRANCH_PATTERN = T.let(/branch\s*=\s*"?([^";]+)"?;/, Regexp)
        REVISION_PATTERN = T.let(/revision\s*=\s*"?([^";]+)"?;/, Regexp)

        sig { params(pbxproj_file: Dependabot::DependencyFile).void }
        def initialize(pbxproj_file)
          @pbxproj_file = pbxproj_file
        end

        # Returns a hash mapping normalized URL to requirement metadata.
        # Each entry includes the Dependabot requirement string and the raw
        # Xcode requirement kind/version info for use in metadata.
        sig { returns(T::Hash[String, T::Hash[Symbol, T.untyped]]) }
        def parse
          content = pbxproj_file.content
          return {} unless content

          requirements = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])

          content.scan(PACKAGE_REF_BLOCK).each do |url, requirement_block|
            url = T.cast(url, String)
            requirement_block = T.cast(requirement_block, String)
            normalized_url = SharedHelpers.scp_to_standard(url)
            name = UrlHelpers.normalize_name(normalized_url)

            req_info = parse_requirement_block(requirement_block)
            next unless req_info

            requirements[name] = req_info.merge(
              url: normalized_url,
              file: pbxproj_file.name
            )
          end

          requirements
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :pbxproj_file

        sig do
          params(block: String)
            .returns(T.nilable(T::Hash[Symbol, T.untyped]))
        end
        def parse_requirement_block(block)
          kind = block.match(KIND_PATTERN)&.captures&.first
          return nil unless kind

          case kind
          when "upToNextMajorVersion"
            build_up_to_next_major(block)
          when "upToNextMinorVersion"
            build_up_to_next_minor(block)
          when "exactVersion"
            build_exact(block)
          when "versionRange"
            build_range(block)
          when "branch"
            build_branch(block)
          when "revision"
            build_revision(block)
          end
        end

        sig { params(block: String).returns(T::Hash[Symbol, T.untyped]) }
        def build_up_to_next_major(block)
          min_version = extract_version(block, MIN_VERSION_PATTERN)
          requirement_string = "from: \"#{min_version}\""
          requirement = parse_native_requirement(requirement_string)

          {
            requirement: requirement,
            requirement_string: requirement_string,
            kind: "upToNextMajorVersion"
          }
        end

        sig { params(block: String).returns(T::Hash[Symbol, T.untyped]) }
        def build_up_to_next_minor(block)
          min_version = extract_version(block, MIN_VERSION_PATTERN)
          requirement_string = ".upToNextMinor(from: \"#{min_version}\")"
          requirement = parse_native_requirement(requirement_string)

          {
            requirement: requirement,
            requirement_string: requirement_string,
            kind: "upToNextMinorVersion"
          }
        end

        sig { params(block: String).returns(T::Hash[Symbol, T.untyped]) }
        def build_exact(block)
          version = extract_version(block, MIN_VERSION_PATTERN) || extract_version(block, VERSION_PATTERN)
          requirement_string = "exact: \"#{version}\""
          requirement = parse_native_requirement(requirement_string)

          {
            requirement: requirement,
            requirement_string: requirement_string,
            kind: "exactVersion"
          }
        end

        sig { params(block: String).returns(T::Hash[Symbol, T.untyped]) }
        def build_range(block)
          min_version = extract_version(block, MIN_VERSION_PATTERN)
          max_version = extract_version(block, MAX_VERSION_PATTERN)
          requirement_string = "\"#{min_version}\"..<\"#{max_version}\""
          requirement = parse_native_requirement(requirement_string)

          {
            requirement: requirement,
            requirement_string: requirement_string,
            kind: "versionRange"
          }
        end

        sig { params(block: String).returns(T::Hash[Symbol, T.untyped]) }
        def build_branch(block)
          branch = block.match(BRANCH_PATTERN)&.captures&.first

          {
            requirement: nil,
            requirement_string: nil,
            kind: "branch",
            branch: branch
          }
        end

        sig { params(block: String).returns(T::Hash[Symbol, T.untyped]) }
        def build_revision(block)
          revision = block.match(REVISION_PATTERN)&.captures&.first

          {
            requirement: nil,
            requirement_string: nil,
            kind: "revision",
            revision: revision
          }
        end

        sig { params(block: String, pattern: Regexp).returns(T.nilable(String)) }
        def extract_version(block, pattern)
          block.match(pattern)&.captures&.first
        end

        # Parses a requirement string into a Dependabot requirement via
        # NativeRequirement. Returns nil if the string is malformed rather
        # than raising, so a single bad entry doesn't stop parsing.
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
