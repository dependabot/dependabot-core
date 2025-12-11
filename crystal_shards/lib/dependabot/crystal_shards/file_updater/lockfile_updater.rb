# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "fileutils"
require "open3"
require "yaml"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/crystal_shards/file_updater"
require "dependabot/crystal_shards/package_manager"

module Dependabot
  module CrystalShards
    class FileUpdater
      class LockfileUpdater
        extend T::Sig

        ALLOWED_GIT_PROTOCOLS = T.let(%w(https).freeze, T::Array[String])
        MAX_FILE_SIZE = 1_048_576
        ALLOWED_GIT_HOSTS = T.let(
          %w(
            github.com
            gitlab.com
            bitbucket.org
          ).freeze,
          T::Array[String]
        )

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependencies:, dependency_files:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
        end

        sig { returns(String) }
        def updated_lockfile_content
          validate_dependency_files!

          first_file = dependency_files.first
          raise Dependabot::DependencyFileNotFound.new(nil, "No dependency files provided") unless first_file

          base_directory = first_file.directory
          SharedHelpers.in_a_temporary_directory(base_directory) do
            write_temporary_dependency_files

            SharedHelpers.with_git_configured(credentials: credentials) do
              run_shards_install
            end

            File.read(LOCKFILE)
          end
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { void }
        def validate_dependency_files!
          manifest = dependency_files.find { |f| f.name == MANIFEST_FILE }
          return unless manifest

          content = manifest.content
          raise Dependabot::DependencyFileNotParseable, MANIFEST_FILE unless content

          if content.bytesize > MAX_FILE_SIZE
            raise Dependabot::DependencyFileNotParseable,
                  "#{MANIFEST_FILE} is too large (max #{MAX_FILE_SIZE} bytes)"
          end

          validate_manifest_content!(content)
        end

        sig { params(content: String).void }
        def validate_manifest_content!(content)
          parsed = YAML.safe_load(content)
          raise Dependabot::DependencyFileNotParseable, MANIFEST_FILE unless parsed.is_a?(Hash)

          %w(dependencies development_dependencies).each do |dep_type|
            deps = parsed[dep_type]
            next unless deps.is_a?(Hash)

            deps.each do |name, details|
              next unless details.is_a?(Hash)

              validate_dependency_source!(name, details)
            end
          end
        rescue Psych::SyntaxError, Psych::DisallowedClass, Psych::BadAlias => e
          raise Dependabot::DependencyFileNotParseable, "#{MANIFEST_FILE}: #{e.message}"
        end

        sig { params(name: String, details: T::Hash[String, T.untyped]).void }
        def validate_dependency_source!(name, details)
          if details["path"]
            validate_path_source!(name, details["path"])
          elsif details["git"]
            validate_git_url!(name, details["git"])
          elsif details["github"]
            validate_shorthand_source!(name, details["github"], "github.com")
          elsif details["gitlab"]
            validate_shorthand_source!(name, details["gitlab"], "gitlab.com")
          elsif details["bitbucket"]
            validate_shorthand_source!(name, details["bitbucket"], "bitbucket.org")
          end
        end

        sig { params(name: String, path: T.untyped).void }
        def validate_path_source!(name, path)
          return unless path.is_a?(String)

          return unless path.include?("..") || path.start_with?("/")

          raise Dependabot::DependencyFileNotResolvable,
                "Dependency '#{name}' has unsafe path: #{path}"
        end

        sig { params(name: String, url: T.untyped).void }
        def validate_git_url!(name, url)
          return unless url.is_a?(String)

          uri = URI.parse(url)

          unless uri.scheme == "https"
            raise Dependabot::DependencyFileNotResolvable,
                  "Dependency '#{name}' must use HTTPS (got: #{uri.scheme})"
          end

          host = uri.host
          unless host && ALLOWED_GIT_HOSTS.include?(host)
            raise Dependabot::DependencyFileNotResolvable,
                  "Dependency '#{name}' uses unsupported host: #{host || 'none'}. " \
                  "Allowed hosts: #{ALLOWED_GIT_HOSTS.join(', ')}"
          end

          if uri.query || uri.fragment
            raise Dependabot::DependencyFileNotResolvable,
                  "Dependency '#{name}' has invalid git URL (query/fragment not allowed)"
          end

          if url.match?(/[;&|`$]/)
            raise Dependabot::DependencyFileNotResolvable,
                  "Dependency '#{name}' has invalid characters in git URL"
          end
        rescue URI::InvalidURIError
          raise Dependabot::DependencyFileNotResolvable,
                "Dependency '#{name}' has invalid git URL: #{url}"
        end

        sig { params(name: String, shorthand: T.untyped, host: String).void }
        def validate_shorthand_source!(name, shorthand, host)
          return unless shorthand.is_a?(String)

          unless shorthand.match?(%r{\A[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+\z})
            raise Dependabot::DependencyFileNotResolvable,
                  "Dependency '#{name}' has invalid #{host} shorthand: #{shorthand}"
          end

          return unless shorthand.include?("..")

          raise Dependabot::DependencyFileNotResolvable,
                "Dependency '#{name}' has unsafe #{host} shorthand: #{shorthand}"
        end

        sig { void }
        def write_temporary_dependency_files
          dependency_files.each do |file|
            path = file.name

            if path.include?("..") || path.start_with?("/")
              raise Dependabot::DependencyFileNotResolvable,
                    "Unsafe file path: #{path}"
            end

            content = file.content
            raise Dependabot::DependencyFileNotParseable, path unless content

            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, content)
          end
        end

        sig { void }
        def run_shards_install
          stdout, stderr, status = Open3.capture3(
            "shards",
            "install",
            "--skip-postinstall",
            "--skip-executables",
            "--no-color"
          )

          return if status.success?

          raise Dependabot::DependencyFileNotResolvable,
                "shards install failed: #{stderr}\n#{stdout}"
        end
      end
    end
  end
end
