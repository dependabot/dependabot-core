# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"
require "dependabot/python/version"
require "dependabot/python/name_normaliser"
require "dependabot/python/file_updater/poetry_file_updater"

module Dependabot
  module Python
    class FileUpdater
      class PoetryFileUpdater
        class LockedVersionChecker
          extend T::Sig

          sig { params(dependencies: T::Array[Dependabot::Dependency]).void }
          def initialize(dependencies:)
            @dependencies = dependencies
          end

          sig { params(lockfile_content: String).returns(String) }
          def check(lockfile_content)
            locked_packages = TomlRB.parse(lockfile_content).fetch("package", [])
            unmet = dependencies.reject do |dep|
              next true unless target_version_required?(dep)

              target = Python::Version.new(T.must(dep.version))
              locked_packages.any? { |pkg| package_matches_target?(pkg, dep, target) }
            end
            return lockfile_content if unmet.empty?

            raise Dependabot::UpdateNotPossible, unmet.map(&:name)
          end

          private

          sig { returns(T::Array[Dependabot::Dependency]) }
          attr_reader :dependencies

          sig { params(dep: Dependabot::Dependency).returns(T::Boolean) }
          def target_version_required?(dep)
            return false if dep.removed? || git_dependency_being_updated?(dep)
            return false unless dep.version
            return false if dep.version == dep.previous_version

            Python::Version.correct?(dep.version)
          end

          sig do
            params(
              pkg: T::Hash[String, T.anything],
              dep: Dependabot::Dependency,
              target: Python::Version
            ).returns(T::Boolean)
          end
          def package_matches_target?(pkg, dep, target)
            package_name = T.cast(pkg["name"], T.nilable(String))
            package_version = T.cast(pkg["version"], T.nilable(String))
            return false unless package_name && package_version && Python::Version.correct?(package_version)

            NameNormaliser.normalise(package_name) == dep.name && Python::Version.new(package_version) == target
          end

          sig { params(dep: Dependabot::Dependency).returns(T::Boolean) }
          def git_dependency_being_updated?(dep)
            dep.requirements.any? { |requirement| requirement.source_string("type") == "git" }
          end
        end
      end
    end
  end
end
