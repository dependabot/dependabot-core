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
            image: String,
            version: String,
            requirement: String,
            manifest: Dependabot::DependencyFile,
            repo_contents_path: String,
            credentials: T::Array[Dependabot::Credential]
          )
            .void
        end
        def initialize(image:, version:, requirement:, manifest:, repo_contents_path:, credentials:)
          @image = image
          @version = version
          @requirement = requirement
          @manifest = manifest
          @repo_contents_path = repo_contents_path
          @credentials = credentials
        end

        sig { returns(T::Array[String]) }
        def update
          SharedHelpers.with_git_configured(credentials: credentials) do
            force_image_target_requirement(manifest.path)
            [File.read(manifest.path)].compact
          end
        end

        private

        sig { params(file_name: String).void }
        def force_image_target_requirement(file_name)
          File.write(file_name, File.read(file_name).gsub("#{@image}", "#{@image.gsub(@version, @requirement)}")
        end

        sig { returns(String) }
        attr_reader :image

        sig { returns(String) }
        attr_reader :requirement

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
