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
            /build.gradle
            /build.gradle.kts
            /settings.gradle
            /settings.gradle.kts
            /gradlew
            /gradlew.bat
            /gradle/wrapper/gradle-wrapper.properties
            /gradle/wrapper/gradle-wrapper.jar
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

          args = %W(wrapper --gradle-version #{version})
          args += %W(--gradle-distribution-sha256-sum #{checksum}) if checksum
          args
        end

        sig do
          override.params(temp_dir: T.any(Pathname, String),
                          build_file: Dependabot::DependencyFile).returns(String)
        end
        def working_dir(temp_dir, build_file)
          super.delete_suffix("gradle/wrapper")
        end

        sig { params(temp_dir: T.any(Pathname, String), files: T::Array[Dependabot::DependencyFile]).void }
        def populate_temp_directory(temp_dir, files)
          # Gradle builds can be complex, to maximize the chances of a successful we just keep related wrapper files
          # and produce a minimal build for it to run (losing any customisations of the `wrapper` task in the process)
          super(temp_dir, files.select { |f| target_file?(f) }
                               .map { |f| cleanup_if_build_file(f) })
        end

        private

        sig { params(file: Dependabot::DependencyFile).returns(Dependabot::DependencyFile) }
        def cleanup_if_build_file(file)
          return file unless File.basename(file.name).start_with?("build.gradle", "settings.gradle")

          cleaned_file = file.dup
          cleaned_file.content = ""
          cleaned_file
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency
      end
    end
  end
end
