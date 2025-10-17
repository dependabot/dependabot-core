# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/registry_client"
require "dependabot/bundler/native_helpers"
require "dependabot/bundler/helpers"
require "dependabot/bundler/update_checker/latest_version_finder"

module Dependabot
  module Bundler
    class UpdateChecker
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        class DependencySource
          extend T::Sig

          require_relative "../shared_bundler_helpers"
          include SharedBundlerHelpers

          RUBYGEMS = "rubygems"
          PRIVATE_REGISTRY = "private"
          GIT = "git"
          OTHER = "other"

          sig { returns(Dependabot::Dependency) }
          attr_reader :dependency

          sig { override.returns(T::Array[Dependabot::DependencyFile]) }
          attr_reader :dependency_files

          sig { override.returns(T.nilable(String)) }
          attr_reader :repo_contents_path

          sig { override.returns(T::Array[Dependabot::Credential]) }
          attr_reader :credentials

          sig { override.returns(T::Hash[Symbol, T.untyped]) }
          attr_reader :options

          sig do
            params(
              dependency: Dependabot::Dependency,
              dependency_files: T::Array[Dependabot::DependencyFile],
              credentials: T::Array[Dependabot::Credential],
              options: T::Hash[Symbol, T.untyped]
            ).void
          end
          def initialize(
            dependency:,
            dependency_files:,
            credentials:,
            options:
          )
            @dependency          = dependency
            @dependency_files    = dependency_files
            @repo_contents_path  = T.let(nil, T.nilable(String))
            @credentials         = credentials
            @options             = options
            @source_type         = T.let(nil, T.nilable(String))
          end

          # The latest version details for the dependency from a registry
          #
          sig { returns(T::Array[Dependabot::Bundler::Version]) }
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
          sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
          def latest_git_version_details
            return unless git?

            source_details =
              dependency.requirements.map { |r| r.fetch(:source) }
                        .uniq.compact.first

            SharedHelpers.with_git_configured(credentials: credentials) do
              in_a_native_bundler_context do |tmp_dir|
                NativeHelpers.run_bundler_subprocess(
                  bundler_version: bundler_version,
                  function: "dependency_source_latest_git_version",
                  options: options,
                  args: {
                    dir: tmp_dir,
                    gemfile_name: T.must(gemfile).name,
                    dependency_name: dependency.name,
                    credentials: credentials,
                    dependency_source_url: source_details[:url],
                    dependency_source_branch: source_details[:branch]
                  }
                )
              end
            end.transform_keys(&:to_sym)
          end

          sig { returns(T::Boolean) }
          def git?
            source_type == GIT
          end

          private

          sig { returns(T::Array[Dependabot::Bundler::Version]) }
          def rubygems_versions
            @rubygems_versions ||= T.let(
              begin
                response = Dependabot::RegistryClient.get(
                  url: dependency_rubygems_uri,
                  headers: { "Accept-Encoding" => "gzip" }
                )

                JSON.parse(response.body)
                    .map { |d| Dependabot::Bundler::Version.new(d["number"]) }
              end,
              T.nilable(T::Array[Dependabot::Bundler::Version])
            )
          rescue JSON::ParserError, Excon::Error::Timeout
            @rubygems_versions = []
          end

          sig { returns(String) }
          def dependency_rubygems_uri
            "https://rubygems.org/api/v1/versions/#{dependency.name}.json"
          end

          sig { returns(T::Array[Dependabot::Bundler::Version]) }
          def private_registry_versions
            @private_registry_versions ||= T.let(
              in_a_native_bundler_context do |tmp_dir|
                NativeHelpers.run_bundler_subprocess(
                  bundler_version: bundler_version,
                  function: "private_registry_versions",
                  options: options,
                  args: {
                    dir: tmp_dir,
                    gemfile_name: T.must(gemfile).name,
                    dependency_name: dependency.name,
                    credentials: credentials
                  }
                ).map do |version_string|
                  Dependabot::Bundler::Version.new(version_string)
                end
              end,
              T.nilable(T::Array[Dependabot::Bundler::Version])
            )
          end

          sig { returns(String) }
          def source_type
            return @source_type if @source_type
            return @source_type = RUBYGEMS unless gemfile

            @source_type = in_a_native_bundler_context do |tmp_dir|
              NativeHelpers.run_bundler_subprocess(
                bundler_version: bundler_version,
                function: "dependency_source_type",
                options: options,
                args: {
                  dir: tmp_dir,
                  gemfile_name: T.must(gemfile).name,
                  dependency_name: dependency.name,
                  credentials: credentials
                }
              )
            end
          end

          sig { returns(T.nilable(Dependabot::DependencyFile)) }
          def gemfile
            dependency_files.find { |f| f.name == "Gemfile" } ||
              dependency_files.find { |f| f.name == "gems.rb" }
          end

          sig { returns(T.nilable(Dependabot::DependencyFile)) }
          def lockfile
            dependency_files.find { |f| f.name == "Gemfile.lock" } ||
              dependency_files.find { |f| f.name == "gems.locked" }
          end

          sig { override.returns(String) }
          def bundler_version
            @bundler_version ||= T.let(
              Helpers.bundler_version(lockfile),
              T.nilable(String)
            )
          end
        end
      end
    end
  end
end
