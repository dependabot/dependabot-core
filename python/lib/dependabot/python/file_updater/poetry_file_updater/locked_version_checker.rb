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

          sig { params(lockfile_content: String).void }
          def check(lockfile_content)
            locked_packages = TomlRB.parse(lockfile_content).fetch("package", [])
            unmet = dependencies.reject do |dep|
              next true unless target_version_required?(dep)

              target = Python::Version.new(T.must(dep.version))
              locked_packages.any? { |pkg| package_matches_target?(pkg, dep, target) }
            end
            return if unmet.empty?

            raise Dependabot::UpdateNotPossible, unmet.map(&:name)
          end

          private

          sig { returns(T::Array[Dependabot::Dependency]) }
          attr_reader :dependencies

          sig { params(dep: Dependabot::Dependency).returns(T::Boolean) }
          def target_version_required?(dep)
            return false if dep.removed? || git_dependency_being_updated?(dep)

            version = dep.version
            return false unless version
            return false if same_python_version?(version, dep.previous_version)

            Python::Version.correct?(version)
          end

          sig { params(version: String, previous_version: T.nilable(String)).returns(T::Boolean) }
          def same_python_version?(version, previous_version)
            return false unless previous_version
            return false unless Python::Version.correct?(version) && Python::Version.correct?(previous_version)

            Python::Version.new(version) == Python::Version.new(previous_version)
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

            locked_version = Python::Version.new(package_version)
            version_matches = if target.local
                                locked_version == target
                              else
                                Python::Version.new(package_version.sub(/\+[^+]+\z/, "")) == target
                              end

            NameNormaliser.normalise(package_name) == dep.name && version_matches
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
