# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/file_updaters/base"
require "dependabot/kotlin_toolchain/constants"
require "dependabot/kotlin_toolchain/wrapper"
require "dependabot/maven/utils/auth_headers_finder"
require "dependabot/registry_client"

module Dependabot
  module KotlinToolchain
    class FileUpdater < Dependabot::FileUpdaters::Base
      class WrapperUpdater
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency:, dependency_files:, credentials:)
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def updated_files
          target_version = T.must(dependency.version)
          repository = Wrapper.detect_repository(wrapper_files)

          updated = wrapper_files.map do |file|
            windows = File.basename(file.name) == WINDOWS_WRAPPER
            content = download(repository: repository, version: target_version, windows: windows, filename: file.name)
            validate_wrapper!(content, target_version, file.name)
            content = with_repository(content, repository, file.name)

            file.dup.tap { |updated_file| updated_file.content = content }
          end

          shas = updated.filter_map { |file| Wrapper.sha_from_content(file.content.to_s) }.uniq
          if shas.length != 1
            raise Dependabot::DependencyFileNotResolvable,
                  "Updated Kotlin Toolchain wrappers contain different checksums"
          end

          updated
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(Dependabot::Maven::Utils::AuthHeadersFinder) }
        def auth_headers_finder
          @auth_headers_finder ||= T.let(
            Dependabot::Maven::Utils::AuthHeadersFinder.new(credentials),
            T.nilable(Dependabot::Maven::Utils::AuthHeadersFinder)
          )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def wrapper_files
          Wrapper.wrapper_files(dependency_files)
        end

        sig { params(repository: String, version: String, windows: T::Boolean, filename: String).returns(String) }
        def download(repository:, version:, windows:, filename:)
          url = Wrapper.artifact_url(repository: repository, version: version, windows: windows)
          response = Dependabot::RegistryClient.get(
            url: url,
            headers: auth_headers_finder.auth_headers(repository)
          )
          unless response.status == 200
            raise Dependabot::DependencyFileNotResolvable,
                  "Unable to download #{filename} for Kotlin Toolchain #{version} from #{url} (HTTP #{response.status})"
          end

          response.body.to_s
        end

        sig { params(content: String, target_version: String, filename: String).void }
        def validate_wrapper!(content, target_version, filename)
          version = Wrapper.version_from_content(content)
          sha = Wrapper.sha_from_content(content)
          return if version == target_version && sha

          raise Dependabot::DependencyFileNotParseable.new(
            filename,
            "Downloaded #{filename} does not contain Kotlin Toolchain #{target_version} and a SHA-256"
          )
        end

        sig { params(content: String, repository: String, filename: String).returns(String) }
        def with_repository(content, repository, filename)
          return content if repository == DEFAULT_DISTRIBUTION_REPOSITORY

          Wrapper.with_repository(content, repository) || raise(
            Dependabot::DependencyFileNotResolvable,
            "Downloaded #{filename} has no distribution repository line to point at #{repository}"
          )
        end
      end
    end
  end
end
