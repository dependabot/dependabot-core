# frozen_string_literal: true

module Dependabot
  module Bundler
    class UpdateChecker
      class LatestVersionFinder
        class DependencySource
          require_relative "../shared_bundler_helpers"
          include SharedBundlerHelpers

          RUBYGEMS = "rubygems"
          PRIVATE_REGISTRY = "private"
          GIT = "git"
          OTHER = "other"

          attr_reader :dependency, :dependency_files, :repo_contents_path,
                      :credentials

          def initialize(dependency:,
                         dependency_files:,
                         credentials:)
            @dependency          = dependency
            @dependency_files    = dependency_files
            @credentials         = credentials
          end

          # The latest version details for the dependency from a registry
          #
          # @return [Array<Gem::Version>]
          def versions
            return rubygems_versions if dependency.name == "bundler"
            return rubygems_versions unless gemfile

            case source_type
            when OTHER, GIT
              []
            when PRIVATE_REGISTRY
              private_registry_versions
            else
              rubygems_versions
            end
          end

          # The latest version details for the dependency from a git repo
          #
          # @return [Hash{Symbol => String}, nil]
          def latest_git_version_details
            return unless git?

            source_details =
              dependency.requirements.map { |r| r.fetch(:source) }.
              uniq.compact.first

            SharedHelpers.with_git_configured(credentials: credentials) do
              in_a_native_bundler_context do |tmp_dir|
                SharedHelpers.run_helper_subprocess(
                  command: NativeHelpers.helper_path,
                  function: "depencency_source_latest_git_version",
                  args: {
                    dir: tmp_dir,
                    gemfile_name: gemfile.name,
                    dependency_name: dependency.name,
                    credentials: credentials,
                    dependency_source_url: source_details[:url],
                    dependency_source_branch: source_details[:branch],
                  }
                )
              end
            end.transform_keys(&:to_sym)
          rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
            if e.message =~ GIT_REF_REGEX
              raise GitDependencyReferenceNotFound, dependency.name
            else
              raise
            end
          end

          def git?
            source_type == GIT
          end

          private

          def rubygems_versions
            @rubygems_versions ||=
              begin
                response = Excon.get(
                  dependency_rubygems_uri,
                  idempotent: true,
                  **SharedHelpers.excon_defaults
                )

                JSON.parse(response.body).
                  map { |d| Gem::Version.new(d["number"]) }
              end
          rescue JSON::ParserError, Excon::Error::Timeout
            @rubygems_versions = []
          end

          def dependency_rubygems_uri
            "https://rubygems.org/api/v1/versions/#{dependency.name}.json"
          end

          def private_registry_versions
            @private_registry_versions ||=
              in_a_native_bundler_context do |tmp_dir|
                SharedHelpers.run_helper_subprocess(
                  command: NativeHelpers.helper_path,
                  function: "private_registry_versions",
                  args: {
                    dir: tmp_dir,
                    gemfile_name: gemfile.name,
                    dependency_name: dependency.name,
                    credentials: credentials,
                  }
                )
              end.map do |version_string|
                Gem::Version.new(version_string)
              end
          rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
            if e.message.match(BundlerErrorPatterns::MISSING_AUTH_REGEX)
              source = Regexp.last_match(:source)
              raise Dependabot::PrivateSourceAuthenticationFailure, source
            elsif e.message.match(BundlerErrorPatterns::BAD_AUTH_REGEX)
              source = Regexp.last_match(:source)
              raise Dependabot::PrivateSourceAuthenticationFailure, source
            elsif e.message.match(BundlerErrorPatterns::HTTP_ERR_REGEX)
              source = Regexp.last_match(:source)
              raise Dependabot::PrivateSourceTimedOut, source
            end

            # TODO: Add testing and further exception case handling

            raise
          end

          def source_type
            return @source_type if defined? @source_type
            return @source_type = RUBYGEMS unless gemfile

            @source_type = in_a_native_bundler_context do |tmp_dir|
              SharedHelpers.run_helper_subprocess(
                command: NativeHelpers.helper_path,
                function: "dependency_source_type",
                args: {
                  dir: tmp_dir,
                  gemfile_name: gemfile.name,
                  dependency_name: dependency.name,
                  credentials: credentials,
                }
              )
            end
          end

          def gemfile
            dependency_files.find { |f| f.name == "Gemfile" } ||
              dependency_files.find { |f| f.name == "gems.rb" }
          end
        end
      end
    end
  end
end
