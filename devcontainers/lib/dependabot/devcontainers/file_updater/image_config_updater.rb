# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"
require "dependabot/logger"
require "dependabot/devcontainers/utils"
require "dependabot/devcontainers/version"

module Dependabot
  module Devcontainers
    class FileUpdater < Dependabot::FileUpdaters::Base
      class ImageConfigUpdater
        extend T::Sig

        sig do
          params(
            current_image: String,
            new_image: String,
            manifest: Dependabot::DependencyFile,
            repo_contents_path: String,
            credentials: T::Array[Dependabot::Credential]
          )
            .void
        end
        def initialize(current_image:, new_image:, manifest:, repo_contents_path:, credentials:)
          @current_image = image
          @new_image = new_image
          @manifest = manifest
          @repo_contents_path = repo_contents_path
          @credentials = credentials
        end

        sig { returns(T::Array[String]) }
        def update
          SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
            SharedHelpers.with_git_configured(credentials: credentials) do
              force_image_target_requirement(manifest_name, from: current_image, to: new_image)
              [File.read(manifest_name)].compact
            end
          end
        end

        private

        sig { returns(String) }
        def base_dir
          File.dirname(manifest.path)
        end

        sig { returns(String) }
        def manifest_name
          File.basename(manifest.path)
        end

        sig { params(file_name: String, from: String, to: T.any(String, Dependabot::Devcontainers::Version)).void }
        def force_image_target_requirement(file_name, from:, to:)
          File.write(file_name, File.read(file_name).gsub(from, to))
        end

        sig { returns(String) }
        attr_reader :current_image

        sig { returns(String) }
        attr_reader :new_image

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :manifest

        sig { returns(String) }
        attr_reader :repo_contents_path

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials
      end
    end
  end
end
