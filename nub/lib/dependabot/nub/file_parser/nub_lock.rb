# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/nub/nub_package_manager"
require "dependabot/nub/native_helpers"
require "dependabot/shared_helpers"

module Dependabot
  module Nub
    class FileParser < Dependabot::FileParsers::Base
      # nub.lock is byte-compatible with the pnpm lockfile v9 format (a rename-only transform of
      # pnpm-lock.yaml). We therefore parse it with the same JS helper the pnpm ecosystem uses:
      # the content is written out as `pnpm-lock.yaml` and handed to `pnpm:parseLockfile`.
      class NubLock
        extend T::Sig

        sig { params(dependency_file: Dependabot::DependencyFile, dealias_packages: T::Boolean).void }
        def initialize(dependency_file, dealias_packages: false)
          @dependency_file = dependency_file
          @dealias_packages = dealias_packages
        end

        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        def parsed
          @parsed ||= T.let(
            T.cast(
              SharedHelpers.in_a_temporary_directory do
                # nub.lock IS a pnpm-lock v9 document; the helper expects it under this name.
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

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependencies
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          # Two passes, mirroring the pnpm parser: DependencySet de-dupes by name and keeps the
          # FIRST-inserted entry's metadata, so specifier-bearing (direct) deps must go in before
          # bare ones — otherwise an aliased package inserted after a same-name plain entry would
          # lose its `{ alias: name }` tag on the merge.
          with_specifiers = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
          without_specifiers = T.let([], T::Array[T::Hash[Symbol, T.untyped]])

          parsed.each do |details|
            next if details["aliased"] && !dealias_packages?

            args = dependency_args(details)
            (details["specifiers"]&.any? ? with_specifiers : without_specifiers) << args
          end

          (with_specifiers + without_specifiers).each do |args|
            dependency_set << Dependency.new(
              name: args[:name],
              version: args[:version],
              package_manager: args[:package_manager],
              requirements: args[:requirements],
              subdependency_metadata: args[:subdependency_metadata],
              metadata: args[:metadata]
            )
          end

          dependency_set
        end

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

          # Single entry: use it even if the lockfile requirement doesn't match.
          if details_candidates.one?
            details_candidates.first
          else
            details_candidates.find { |info| info["specifiers"]&.include?(requirement) }
          end
        end

        private

        # Builds the Dependency.new kwargs for one parsed lockfile entry. Metadata/subdependency
        # keys are set only when present so Dependency.new applies its own defaults.
        sig { params(details: T::Hash[String, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
        def dependency_args(details)
          name = T.cast(details["name"], String)
          args = {
            name: name,
            version: T.cast(details["version"], T.nilable(String)),
            package_manager: NubPackageManager::NAME,
            requirements: []
          }
          args[:metadata] = { alias: name } if details["aliased"]
          args[:subdependency_metadata] = [{ production: !details["dev"] }] if details["dev"]
          args
        end

        sig { returns(T::Boolean) }
        def dealias_packages?
          @dealias_packages
        end
      end
    end
  end
end
