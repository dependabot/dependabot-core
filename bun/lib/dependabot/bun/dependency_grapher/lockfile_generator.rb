# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/shared_helpers"
require "dependabot/bun/helpers"
require "dependabot/bun/bun_package_manager"

module Dependabot
  module Bun
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      class LockfileGenerator
        extend T::Sig

        sig do
          params(
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency_files:, credentials:)
          @dependency_files = dependency_files
          @credentials = credentials
        end

        sig { returns(Dependabot::DependencyFile) }
        def generate
          SharedHelpers.in_a_temporary_directory do
            write_temporary_files
            run_lockfile_generation
            read_generated_lockfile
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_generation_error(e)
          raise
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { void }
        def write_temporary_files
          dependency_files.each do |file|
            next unless file.name.end_with?("package.json", ".npmrc")

            path = file.name
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, file.content)
          end
        end

        sig { void }
        def run_lockfile_generation
          Dependabot.logger.info("Generating bun.lock for dependency graphing")
          Helpers.run_bun_command("install --ignore-scripts", fingerprint: "install --ignore-scripts")
        end

        sig { returns(Dependabot::DependencyFile) }
        def read_generated_lockfile
          lockfile_name = BunPackageManager::LOCKFILE_NAME

          unless File.exist?(lockfile_name)
            Dependabot.logger.error("#{lockfile_name} was not generated")
            raise Dependabot::DependencyFileNotEvaluatable, "#{lockfile_name} was not generated"
          end

          Dependabot::DependencyFile.new(
            name: lockfile_name,
            content: File.read(lockfile_name),
            directory: package_json_directory
          )
        end

        sig { returns(String) }
        def package_json_directory
          package_json = dependency_files.find { |f| f.name.end_with?("package.json") }
          package_json&.directory || "/"
        end

        sig { params(error: SharedHelpers::HelperSubprocessFailed).void }
        def handle_generation_error(error)
          Dependabot.logger.error("Failed to generate bun.lock: #{error.message}")
        end
      end
    end
  end
end
