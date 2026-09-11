# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/npm_and_yarn/file_parser"
require "dependabot/errors"
require "dependabot/dependency"
require "dependabot/npm_and_yarn/native_helpers"
require "dependabot/package/npm_lockfile_details"
require "dependabot/shared_helpers"

module Dependabot
  module NpmAndYarn
    class FileParser < Dependabot::FileParsers::Base
      class PnpmLock
        extend T::Sig

        class Record < T::ImmutableStruct
          extend T::Sig

          const :name, String
          const :version, String
          const :resolved, T.nilable(String)
          const :dev, T::Boolean
          const :specifiers, T::Array[String]
          const :aliased, T::Boolean

          sig { params(value: Object, path: String, index: Integer).returns(Record) }
          def self.from_object(value, path:, index:)
            context = "pnpm helper result[#{index}]"
            raise DependencyFileNotParseable.new(path, "#{context} must be an object") unless value.is_a?(Hash)

            resolved = string(T.cast(value["resolved"], Object), path, "#{context}.resolved") if value.key?("resolved")

            new(
              name: string(T.cast(value["name"], Object), path, "#{context}.name"),
              version: string(T.cast(value["version"], Object), path, "#{context}.version"),
              resolved: resolved,
              dev: boolean(T.cast(value["dev"], Object), path, "#{context}.dev"),
              specifiers: strings(T.cast(value["specifiers"], Object), path, "#{context}.specifiers"),
              aliased: boolean(T.cast(value["aliased"], Object), path, "#{context}.aliased")
            )
          end

          sig { params(value: Object, path: String, field: String).returns(String) }
          def self.string(value, path, field)
            return value if value.is_a?(String)

            raise DependencyFileNotParseable.new(path, "#{field} must be a string")
          end
          private_class_method :string

          sig { params(value: Object, path: String, field: String).returns(T::Boolean) }
          def self.boolean(value, path, field)
            return value if value.is_a?(TrueClass) || value.is_a?(FalseClass)

            raise DependencyFileNotParseable.new(path, "#{field} must be a boolean")
          end
          private_class_method :boolean

          sig { params(value: Object, path: String, field: String).returns(T::Array[String]) }
          def self.strings(value, path, field)
            raise DependencyFileNotParseable.new(path, "#{field} must be an array") unless value.is_a?(Array)

            value.each_with_index.map do |specifier, index|
              string(T.cast(specifier, Object), path, "#{field}[#{index}]")
            end
          end
          private_class_method :strings
        end

        sig { params(dependency_file: Dependabot::DependencyFile, dealias_packages: T::Boolean).void }
        def initialize(dependency_file, dealias_packages: false)
          @dependency_file = dependency_file
          @dealias_packages = dealias_packages
          @parsed = T.let(nil, T.nilable(T::Array[Record]))
        end

        sig { returns(T::Array[Record]) }
        def parsed
          return @parsed if @parsed

          result = SharedHelpers.in_a_temporary_directory do
            File.write("pnpm-lock.yaml", @dependency_file.content)

            SharedHelpers.run_helper_subprocess(
              command: NativeHelpers.helper_path,
              function: "pnpm:parseLockfile",
              args: [Dir.pwd]
            )
          rescue SharedHelpers::HelperSubprocessFailed
            raise Dependabot::DependencyFileNotParseable, @dependency_file.path
          end

          unless result.is_a?(Array)
            raise DependencyFileNotParseable.new(@dependency_file.path, "pnpm helper result must be an array")
          end

          @parsed = result.each_with_index.map do |record, index|
            Record.from_object(T.cast(record, Object), path: @dependency_file.path, index: index)
          end
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependencies
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new
          with_specifiers, without_specifiers = parsed.partition { |record| record.specifiers.any? }

          (with_specifiers + without_specifiers).each do |record|
            next if record.aliased && !dealias_packages?

            dependency_set << Dependency.new(
              name: record.name,
              version: record.version,
              package_manager: "npm_and_yarn",
              requirements: [],
              subdependency_metadata: record.dev ? [{ production: false }] : nil,
              metadata: record.aliased ? { alias: record.name } : nil
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
            .returns(T.nilable(Dependabot::Package::NpmLockfileDetails))
        end
        def details(dependency_name, requirement, _manifest_name)
          details_candidates = parsed.select { |record| record.name == dependency_name }

          # If there's only one entry for this dependency, use it, even if
          # the requirement in the lockfile doesn't match
          details = if details_candidates.one?
                      details_candidates.first
                    elsif requirement
                      details_candidates.find { |record| record.specifiers.include?(requirement) }
                    end
          return if details.nil?

          Dependabot::Package::NpmLockfileDetails.new(version: details.version, resolved: details.resolved)
        end

        private

        sig { returns(T::Boolean) }
        def dealias_packages?
          @dealias_packages
        end
      end
    end
  end
end
