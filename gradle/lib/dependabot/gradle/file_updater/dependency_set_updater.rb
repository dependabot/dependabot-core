# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/gradle/file_parser"
require "dependabot/gradle/file_updater"

module Dependabot
  module Gradle
    class FileUpdater
      class DependencySetUpdater
        extend T::Sig

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        sig do
          params(
            dependency_set: T::Hash[Symbol, String],
            buildfile: Dependabot::DependencyFile,
            previous_requirement: String,
            updated_requirement: String
          ).returns(T::Array[Dependabot::DependencyFile])
        end
        def update_files_for_dep_set_change(dependency_set:,
                                            buildfile:,
                                            previous_requirement:,
                                            updated_requirement:)
          declaration_string =
            original_declaration_string(dependency_set, buildfile)

          return dependency_files unless declaration_string

          updated_content = T.must(buildfile.content).sub(
            declaration_string,
            declaration_string.sub(
              previous_requirement,
              updated_requirement
            )
          )

          updated_files = dependency_files.dup
          updated_files[T.must(updated_files.index(buildfile))] =
            update_file(file: buildfile, content: updated_content)

          updated_files
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig do
          params(
            dependency_set: T::Hash[Symbol, String],
            buildfile: Dependabot::DependencyFile
          )
            .returns(T.nilable(String))
        end
        def original_declaration_string(dependency_set, buildfile)
          regex = Gradle::FileParser::DEPENDENCY_SET_DECLARATION_REGEX
          dependency_sets = T.let([], T::Array[String])
          T.must(buildfile.content).scan(regex) do
            dependency_sets << Regexp.last_match.to_s
          end

          dependency_sets.find do |mtch|
            next unless mtch.include?(T.must(dependency_set[:group]))

            mtch.include?(T.must(dependency_set[:version]))
          end
        end

        sig { params(file: Dependabot::DependencyFile, content: String).returns(Dependabot::DependencyFile) }
        def update_file(file:, content:)
          updated_file = file.dup
          updated_file.content = content
          updated_file
        end
      end
    end
  end
end
