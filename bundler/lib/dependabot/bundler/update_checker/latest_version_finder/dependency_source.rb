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

            dependency_source_details =
              dependency.requirements.map { |r| r.fetch(:source) }.
              uniq.compact.first

            in_a_temporary_bundler_context do
              SharedHelpers.with_git_configured(credentials: credentials) do
                # Note: we don't set `ref`, as we want to unpin the dependency
                source = ::Bundler::Source::Git.new(
                  "uri" => dependency_source_details[:url],
                  "branch" => dependency_source_details[:branch],
                  "name" => dependency.name,
                  "submodules" => true
                )

                # Tell Bundler we're fine with fetching the source remotely
                source.instance_variable_set(:@allow_remote, true)

                spec = source.specs.first
                { version: spec.version, commit_sha: spec.source.revision }
              end
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
              in_a_temporary_bundler_context do
                bundler_source.
                  fetchers.flat_map do |fetcher|
                    fetcher.
                      specs_with_retry([dependency.name], bundler_source).
                      search_all(dependency.name)
                  end.
                  map(&:version)
              end
          end

          def bundler_source
            return nil unless gemfile

            @bundler_source ||=
              in_a_temporary_bundler_context do
                definition = ::Bundler::Definition.build(gemfile.name, nil, {})

                specified_source =
                  definition.dependencies.
                  find { |dep| dep.name == dependency.name }&.source

                specified_source || definition.send(:sources).default_source
              end
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

            puts @source_type

            @source_type
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
