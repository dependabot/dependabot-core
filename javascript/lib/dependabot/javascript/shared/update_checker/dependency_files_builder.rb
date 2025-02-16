# typed: strict
# frozen_string_literal: true

module Dependabot
  module Javascript
    module Shared
      module UpdateChecker
        class DependencyFilesBuilder
          extend T::Helpers
          extend T::Sig

          abstract!

          Credentials = T.type_alias { T::Array[Credential] }

          sig do
            params(
              dependency: Dependency,
              dependency_files: T::Array[DependencyFile],
              credentials: Credentials
            )
              .void
          end
          def initialize(dependency:, dependency_files:, credentials:)
            @dependency = T.let(dependency, Dependency)
            @dependency_files = T.let(dependency_files, T::Array[DependencyFile])
            @credentials = T.let(credentials, Credentials)
          end

          sig { void }
          def write_temporary_dependency_files
            write_lockfiles

            File.write(".npmrc", npmrc_content)

            package_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(file.name, prepared_package_json_content(file))
            end
          end

          sig { abstract.returns(T::Array[DependencyFile]) }
          def lockfiles; end

          sig { returns(T::Array[DependencyFile]) }
          def package_files
            @package_files ||= T.let(
              dependency_files
              .select { |f| f.name.end_with?("package.json") },
              T.nilable(T::Array[DependencyFile])
            )
          end

          private

          sig { returns(Dependency) }
          attr_reader :dependency

          sig { returns(T::Array[DependencyFile]) }
          attr_reader :dependency_files

          sig { returns(Credentials) }
          attr_reader :credentials

          sig { abstract.returns(T::Array[DependencyFile]) }
          def write_lockfiles; end

          sig { params(file: DependencyFile).returns(String) }
          def prepared_package_json_content(file)
            FileUpdater::PackageJsonPreparer.new(
              package_json_content: file.content
            ).prepared_content
          end

          sig { returns(String) }
          def npmrc_content
            FileUpdater::NpmrcBuilder.new(
              credentials: credentials,
              dependency_files: dependency_files
            ).npmrc_content
          end
        end
      end
    end
  end
end
