# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "shellwords"

require "dependabot/gradle/distributions"
require "dependabot/gradle/file_updater/gradle_updater_base"

module Dependabot
  module Gradle
    class FileUpdater
      class WrapperUpdater < GradleUpdaterBase
        extend T::Sig
        include Dependabot::Gradle::Distributions

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile], dependency: Dependabot::Dependency).void }
        def initialize(dependency_files:, dependency:)
          super(dependency_files: dependency_files)
          @dependency = dependency
          @target_files = T.let(%w(
            /gradlew
            /gradlew.bat
            /gradle/wrapper/gradle-wrapper.properties
            /gradle/wrapper/gradle-wrapper.jar
          ), T::Array[String])
          @build_files = T.let(%w(
            build.gradle
            build.gradle.kts
            settings.gradle
            settings.gradle.kts
          ), T::Array[String])
        end

        sig { override.params(file: Dependabot::DependencyFile).returns(T::Boolean) }
        def target_file?(file)
          @target_files.any? { |r| "/#{file.name}".end_with?(r) }
        end

        sig { override.returns(T::Array[String]) }
        def command_args
          version = T.let(dependency.requirements[0]&.[](:requirement), String)
          checksum = T.let(dependency.requirements[1]&.[](:requirement), String) if dependency.requirements.size > 1

          args = %W(wrapper --no-validate-url --gradle-version #{version})
          args += %W(--gradle-distribution-sha256-sum #{checksum}) if checksum
          args
        end

        sig { params(build_file: Dependabot::DependencyFile).returns(String) }
        def base_path(build_file)
          super.delete_suffix("/gradle/wrapper")
        end

        private

        # Gradle builds can be complex, to maximize the chances of a successful we just keep related wrapper files
        # and produce a minimal build for it to run (losing any customisations of the `wrapper` task in the process)
        sig { override.returns(T::Array[Dependabot::DependencyFile]) }
        def files_to_populate
          @dependency_files.filter_map do |f|
            next f if target_file?(f)
            next Dependabot::DependencyFile.new(directory: f.directory, name: f.name, content: "") if build_file?(f)
          end
        end

        sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
        def build_file?(file)
          @build_files.include?(File.basename(file.name))
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency
      end
    end
  end
end
