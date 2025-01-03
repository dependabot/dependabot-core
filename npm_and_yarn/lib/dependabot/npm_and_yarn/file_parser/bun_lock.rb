# typed: strict
# frozen_string_literal: true

require "yaml"
require "dependabot/errors"
require "dependabot/npm_and_yarn/helpers"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class FileParser < Dependabot::FileParsers::Base
      class BunLock
        extend T::Sig

        sig { params(dependency_file: DependencyFile).void }
        def initialize(dependency_file)
          @dependency_file = dependency_file
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def parsed
          # Since bun.lock is a JSONC file, which is a subset of YAML, we can use YAML to parse it
          json_obj = YAML.load(T.must(@dependency_file.content))
          @parsed ||= T.let(json_obj, T.nilable(T::Hash[String, T.untyped]))
        rescue Psych::SyntaxError
          raise Dependabot::DependencyFileNotParseable.new(@dependency_file.path, "Invalid bun.lock file")
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependencies
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          lockfile_version = parsed["lockfileVersion"]
          if lockfile_version.zero?
            packages = parsed["packages"]
            raise_invalid_lock!("expected 'packages' to be an object") unless packages.is_a?(Hash)

            packages.each do |key, details|
              raise_invalid_lock!("expected 'packages.#{key}' to be an array") unless details.is_a?(Array)

              entry = details.first
              raise_invalid_lock!("expected 'packages.#{key}[0]' to be a string") unless entry.is_a?(String)

              name, version = entry.split(/(?<=\w)\@/)
              next if name.empty? || version.start_with?("workspace:")

              dependency_set << Dependency.new(
                name: name,
                version: version,
                package_manager: "npm_and_yarn",
                requirements: []
              )
            end
          else
            raise_invalid_lock!("expected 'lockfileVersion' to be 0")
          end

          dependency_set
        end

        sig do
          params(dependency_name: String, requirement: T.untyped, _manifest_name: String)
            .returns(T.nilable(T::Hash[String, T.untyped]))
        end
        def details(dependency_name, requirement, _manifest_name)
          lockfile_version = parsed["lockfileVersion"]
          return unless lockfile_version.zero?

          packages = parsed["packages"]
          return unless packages.is_a?(Hash)

          candidates =
            packages
            .select { |name, _| name == dependency_name }
            .values

          # If there's only one entry for this dependency, use it, even if
          # the requirement in the lockfile doesn't match
          if candidates.one?
            format_details(lockfile_version, candidates.first)
          else
            candidate = candidates.find do |label, _|
              label.scan(/(?<=\w)\@(?:npm:)?([^\s,]+)/).flatten.include?(requirement)
            end&.last
            format_details(lockfile_version, candidate)
          end
        end

        private

        sig { params(message: String).void }
        def raise_invalid_lock!(message)
          raise Dependabot::DependencyFileNotParseable.new(@dependency_file.path, "Invalid bun.lock file: #{message}")
        end

        sig { params(lockfile_version: T.nilable(Integer), entry: T.nilable(T::Array[T.untyped])).returns(T.nilable(T::Hash[String, T.untyped])) }
        def format_details(lockfile_version, entry)
          return unless lockfile_version.zero?
          return unless entry.is_a?(Array)

          label, registry, details, hash = entry
          name, version = label.split(/(?<=\w)\@/)
          {
            "name" => name,
            "version" => version,
            "registry" => registry,
            "details" => details,
            "hash" => hash
          }
        end
      end
    end
  end
end
