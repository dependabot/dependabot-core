# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/npm_and_yarn/native_helpers"
require "dependabot/shared_helpers"

module Dependabot
  module NpmAndYarn
    class FileParser < Dependabot::FileParsers::Base
      class PnpmLock
        extend T::Sig

        sig { params(dependency_file: Dependabot::DependencyFile).void }
        def initialize(dependency_file)
          @dependency_file = dependency_file
        end

        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        def parsed
          @parsed ||= T.let(
            T.cast(
              SharedHelpers.in_a_temporary_directory do
                File.write("pnpm-lock.yaml", @dependency_file.content)

                SharedHelpers.run_helper_subprocess(
                  command: NativeHelpers.helper_path,
                  function: "pnpm:parseLockfile",
                  args: [Dir.pwd]
                )
              rescue SharedHelpers::HelperSubprocessFailed
                raise Dependabot::DependencyFileNotParseable, @dependency_file.path
              end,
              T::Array[T::Hash[String, T.untyped]]
            ),
            T.nilable(T::Array[T::Hash[String, T.untyped]])
          )
        end

        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/AbcSize
        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependencies
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          # Separate dependencies into two categories: with specifiers and without specifiers.
          dependencies_with_specifiers = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
          dependencies_without_specifiers = T.let([], T::Array[T::Hash[Symbol, T.untyped]])

          parsed.each do |details|
            next if details["aliased"]

            name = T.cast(details["name"], String)
            version = T.cast(details["version"], T.nilable(String))

            dependency_args = {
              name: name,
              version: version,
              package_manager: "npm_and_yarn",
              requirements: []
            }

            # Add metadata for subdependencies if marked as a dev dependency.
            dependency_args[:subdependency_metadata] = [{ production: !details["dev"] }] if details["dev"]

            specifiers = details["specifiers"]
            if specifiers&.any?
              dependencies_with_specifiers << dependency_args
            else
              dependencies_without_specifiers << dependency_args
            end
          end

          origin_file = Pathname.new(@dependency_file.directory).join(@dependency_file.name).to_s

          # Add prioritized dependencies to the dependency set.
          dependencies_with_specifiers.each do |dependency_args|
            dependency_set << Dependency.new(
              name: dependency_args[:name],
              version: dependency_args[:version],
              package_manager: dependency_args[:package_manager],
              requirements: dependency_args[:requirements],
              subdependency_metadata: dependency_args[:subdependency_metadata],
              origin_files: [origin_file]
            )
          end

          dependencies_without_specifiers.each do |dependency_args|
            dependency_set << Dependency.new(
              name: dependency_args[:name],
              version: dependency_args[:version],
              package_manager: dependency_args[:package_manager],
              requirements: dependency_args[:requirements],
              subdependency_metadata: dependency_args[:subdependency_metadata],
              origin_files: [origin_file]
            )
          end

          dependency_set
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/MethodLength

        sig do
          params(
            dependency_name: String,
            requirement: T.nilable(String),
            _manifest_name: T.nilable(String)
          )
            .returns(T.nilable(T::Hash[String, T.untyped]))
        end
        def details(dependency_name, requirement, _manifest_name)
          details_candidates = parsed.select { |info| info["name"] == dependency_name }

          # If there's only one entry for this dependency, use it, even if
          # the requirement in the lockfile doesn't match
          if details_candidates.one?
            details_candidates.first
          else
            details_candidates.find { |info| info["specifiers"]&.include?(requirement) }
          end
        end
      end
    end
  end
end
