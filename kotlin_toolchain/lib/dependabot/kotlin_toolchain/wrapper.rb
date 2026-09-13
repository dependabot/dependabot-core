# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/kotlin_toolchain/constants"

module Dependabot
  module KotlinToolchain
    module Wrapper
      extend T::Sig

      UNIX_VERSION = /^kotlin_cli_version=(?<version>[^\s#]+)\s*$/
      WINDOWS_VERSION = /^set\s+kotlin_cli_version=(?<version>[^\s\r]+)\s*$/i
      UNIX_SHA = /^kotlin_cli_sha256=(?<sha>[0-9a-f]{64})\s*$/i
      WINDOWS_SHA = /^set\s+kotlin_cli_sha256=(?<sha>[0-9a-f]{64})\s*$/i
      UNIX_REPOSITORY = %r!
        ^KOTLIN_CLI_DOWNLOAD_ROOT="\$\{KOTLIN_CLI_DOWNLOAD_ROOT:-(?<repository>https?://[^"}]+)\}"
      !x
      WINDOWS_REPOSITORY = %r{
        ^if\s+not\s+defined\s+KOTLIN_CLI_DOWNLOAD_ROOT\s+
        set\s+"?KOTLIN_CLI_DOWNLOAD_ROOT=(?<repository>https?://[^\s"]+)"?\s*$
      }ix

      sig { params(content: String).returns(T.nilable(String)) }
      def self.version_from_content(content)
        match = content.match(UNIX_VERSION) || content.match(WINDOWS_VERSION)
        match&.named_captures&.fetch("version")
      end

      sig { params(content: String).returns(T.nilable(String)) }
      def self.sha_from_content(content)
        match = content.match(UNIX_SHA) || content.match(WINDOWS_SHA)
        match&.named_captures&.fetch("sha")&.downcase
      end

      sig { params(content: String).returns(T.nilable(String)) }
      def self.repository_from_content(content)
        match = content.match(UNIX_REPOSITORY) || content.match(WINDOWS_REPOSITORY)
        repository = match&.named_captures&.fetch("repository")
        repository && without_trailing_slashes(repository)
      end

      sig { params(content: String, repository: String).returns(T.nilable(String)) }
      def self.with_repository(content, repository)
        match = content.match(UNIX_REPOSITORY) || content.match(WINDOWS_REPOSITORY)
        return unless match

        start, finish = match.offset(:repository)
        content.dup.tap { |updated| updated[T.must(start)...T.must(finish)] = repository }
      end

      sig { params(files: T::Array[Dependabot::DependencyFile]).returns(String) }
      def self.detect_version(files)
        detect_matching_value(
          files,
          description: "versions",
          missing_message: "Kotlin Toolchain wrapper is missing",
          parser: ->(content) { version_from_content(content) }
        )
      end

      sig { params(files: T::Array[Dependabot::DependencyFile]).returns(String) }
      def self.detect_sha(files)
        detect_matching_value(
          files,
          description: "checksums",
          missing_message: "Kotlin Toolchain wrapper checksum is missing",
          parser: ->(content) { sha_from_content(content) }
        )
      end

      sig { params(files: T::Array[Dependabot::DependencyFile]).returns(String) }
      def self.detect_repository(files)
        wrappers = wrapper_files(files)
        raise Dependabot::DependencyFileNotFound.new(nil, "Kotlin Toolchain wrapper is missing") if wrappers.empty?

        values = wrappers.filter_map { |file| repository_from_content(file.content.to_s) }.uniq
        if values.length > 1
          raise Dependabot::DependencyFileNotParseable.new(
            T.must(wrappers.first).name,
            "Kotlin Toolchain wrappers contain different distribution repositories: #{values.join(', ')}"
          )
        end

        values.first || DEFAULT_DISTRIBUTION_REPOSITORY
      end

      sig { params(files: T::Array[Dependabot::DependencyFile]).returns(T::Array[Dependabot::DependencyFile]) }
      def self.wrapper_files(files)
        files.select { |file| WRAPPER_FILES.include?(File.basename(file.name)) }
      end

      sig do
        params(
          files: T::Array[Dependabot::DependencyFile],
          description: String,
          missing_message: String,
          parser: T.proc.params(content: String).returns(T.nilable(String))
        ).returns(String)
      end
      private_class_method def self.detect_matching_value(files, description:, missing_message:, parser:)
        wrappers = wrapper_files(files)
        values = wrappers.filter_map do |file|
          value = parser.call(file.content.to_s)
          unless value
            raise Dependabot::DependencyFileNotParseable.new(file.name, "#{file.name}: missing #{description}")
          end

          value
        end.uniq

        raise Dependabot::DependencyFileNotFound.new(nil, missing_message) if values.empty?

        if values.length > 1
          raise Dependabot::DependencyFileNotParseable.new(
            T.must(wrappers.first).name,
            "Kotlin Toolchain wrappers contain different #{description}: #{values.join(', ')}"
          )
        end

        T.must(values.first)
      end

      sig { params(version: String, windows: T::Boolean).returns(String) }
      def self.artifact_name(version:, windows:)
        suffix = windows ? "-wrapper.bat" : "-wrapper"
        "kotlin-cli-#{version}#{suffix}"
      end

      sig { params(repository: String, version: String, windows: T::Boolean).returns(String) }
      def self.artifact_url(repository:, version:, windows:)
        artifact = artifact_name(version: version, windows: windows)
        "#{without_trailing_slashes(repository)}/org/jetbrains/kotlin/kotlin-cli/#{version}/#{artifact}"
      end

      sig { params(value: String).returns(String) }
      def self.without_trailing_slashes(value)
        value = value.delete_suffix("/") while value.end_with?("/")
        value
      end
    end
  end
end
