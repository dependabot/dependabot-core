# typed: strict
# frozen_string_literal: true

require "parseconfig"
require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/git_submodules/package_manager"

module Dependabot
  module GitSubmodules
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        Dependabot::SharedHelpers.in_a_temporary_directory do
          File.write(".gitmodules", gitmodules_file.content)

          ParseConfig.new(".gitmodules").params.map do |_, params|
            raise DependencyFileNotParseable, gitmodules_file.path if params.fetch("path").end_with?("/")

            Dependency.new(
              name: params.fetch("path"),
              version: submodule_sha(params.fetch("path")),
              package_manager: "submodules",
              requirements: [{
                requirement: nil,
                file: ".gitmodules",
                source: {
                  type: "git",
                  url: absolute_url(params["url"]),
                  branch: params["branch"],
                  ref: params["branch"]
                },
                groups: []
              }]
            )
          end
        end
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(begin
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager
          )
        end, T.nilable(Dependabot::Ecosystem))
      end

      private

      sig { params(url: String).returns(String) }
      def absolute_url(url)
        # Submodules can be specified with a relative URL (e.g., ../repo.git)
        # which we want to expand out into a full URL if present.
        return url unless url.start_with?("../", "./")

        path = Pathname.new(File.join(source&.repo, url))
        "https://#{source&.hostname}/#{path.cleanpath}"
      end

      sig { params(path: String).returns(T.nilable(String)) }
      def submodule_sha(path)
        submodule = dependency_files.find { |f| f.name == path }
        raise "Submodule not found #{path}" unless submodule

        submodule.content
      end

      sig { returns(Dependabot::DependencyFile) }
      def gitmodules_file
        @gitmodules_file ||=
          T.let(
            T.must(get_original_file(".gitmodules")),
            T.nilable(Dependabot::DependencyFile)
          )
      end

      sig { override.void }
      def check_required_files
        %w(.gitmodules).each do |filename|
          raise "No #{filename}!" unless get_original_file(filename)
        end
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          PackageManager.new(T.must(git_version)),
          T.nilable(Dependabot::GitSubmodules::PackageManager)
        )
      end

      sig { returns(T.nilable(String)) }
      def git_version
        @git_version ||= T.let(
          begin
            version = SharedHelpers.run_shell_command("git --version")
            version.match(Dependabot::Ecosystem::VersionManager::DEFAULT_VERSION_PATTERN)&.captures&.first
          end,
          T.nilable(String)
        )
      end
    end
  end
end

Dependabot::FileParsers
  .register("submodules", Dependabot::GitSubmodules::FileParser)
