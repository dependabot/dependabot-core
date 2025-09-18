# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/hex/update_checker"
require "dependabot/hex/file_updater/mixfile_requirement_updater"
require "dependabot/hex/file_updater/mixfile_git_pin_updater"
require "dependabot/hex/file_updater/mixfile_sanitizer"
require "dependabot/hex/version"

module Dependabot
  module Hex
    class UpdateChecker
      # This class takes a set of dependency files and sanitizes them for use
      # in UpdateCheckers::Elixir::Hex.
      class FilePreparer
        extend T::Sig

        sig do
          params(
            dependency_files: T::Array[Dependabot::DependencyFile],
            dependency: Dependabot::Dependency,
            unlock_requirement: T.any(T.nilable(Symbol), T::Boolean),
            replacement_git_pin: T.nilable(String),
            latest_allowable_version: T.nilable(Gem::Version)
          ).void
        end
        def initialize(dependency_files:, dependency:,
                       unlock_requirement: true,
                       replacement_git_pin: nil,
                       latest_allowable_version: nil)
          @dependency_files = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
          @dependency = T.let(dependency, Dependabot::Dependency)
          @unlock_requirement = T.let(unlock_requirement ? true : false, T::Boolean)
          @replacement_git_pin = T.let(replacement_git_pin, T.nilable(String))
          @latest_allowable_version = T.let(latest_allowable_version, T.nilable(Gem::Version))
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def prepared_dependency_files
          files = []
          files += mixfiles.map do |file|
            DependencyFile.new(
              name: file.name,
              content: mixfile_content_for_update_check(file),
              directory: file.directory
            )
          end
          files << lockfile if lockfile
          files += support_files
          files
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T.nilable(String)) }
        attr_reader :replacement_git_pin

        sig { returns(T.nilable(Gem::Version)) }
        attr_reader :latest_allowable_version

        sig { returns(T::Boolean) }
        def unlock_requirement?
          @unlock_requirement
        end

        sig { returns(T::Boolean) }
        def replace_git_pin?
          !replacement_git_pin.nil?
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def mixfile_content_for_update_check(file)
          content = T.must(file.content)

          return sanitize_mixfile(content) unless dependency_appears_in_file?(file.name)

          content = relax_version(content, filename: file.name)
          content = replace_git_pin(content, filename: file.name) if replace_git_pin?

          sanitize_mixfile(content)
        end

        sig { params(content: String, filename: String).returns(String) }
        def relax_version(content, filename:)
          old_requirement =
            dependency.requirements.find { |r| r.fetch(:file) == filename }
                      &.fetch(:requirement)
          updated_requirement = updated_version_requirement_string(filename)

          Hex::FileUpdater::MixfileRequirementUpdater.new(
            dependency_name: dependency.name,
            mixfile_content: content,
            previous_requirement: old_requirement,
            updated_requirement: updated_requirement,
            insert_if_bare: !updated_requirement.nil?
          ).updated_content
        end

        sig { params(filename: String).returns(T.nilable(String)) }
        def updated_version_requirement_string(filename)
          lower_bound_req = updated_version_req_lower_bound(filename)

          return lower_bound_req if latest_allowable_version.nil?
          return lower_bound_req unless version_class.correct?(latest_allowable_version)

          lower_bound_req + " and <= #{latest_allowable_version}"
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/CyclomaticComplexity
        sig { params(filename: String).returns(String) }
        def updated_version_req_lower_bound(filename)
          original_req = dependency.requirements
                                   .find { |r| r.fetch(:file) == filename }
                                   &.fetch(:requirement)

          if original_req && !unlock_requirement? then original_req
          elsif dependency.version&.match?(/^[0-9a-f]{40}$/) then ">= 0"
          elsif dependency.version then ">= #{dependency.version}"
          else
            version_for_requirement =
              dependency.requirements.filter_map { |r| r[:requirement] }
                        .reject { |req_string| req_string.start_with?("<") }
                        .select { |req_string| req_string.match?(version_regex) }
                        .map { |req_string| req_string.match(version_regex) }
                        .select { |version| version_class.correct?(version.to_s) }
                        .max_by { |version| version_class.new(version.to_s) }

            return ">= 0" unless version_for_requirement

            # Elixir requires that versions are specified to three places
            # when used with a >= specifier
            parts = version_for_requirement.to_s.split(".")
            parts << "0" while parts.count < 3
            ">= #{parts.join('.')}"
          end
        end
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/AbcSize

        sig { params(content: String, filename: String).returns(String) }
        def replace_git_pin(content, filename:)
          old_pin =
            dependency.requirements.find { |r| r.fetch(:file) == filename }
                      &.dig(:source, :ref)

          return content unless old_pin
          return content if old_pin == replacement_git_pin

          Hex::FileUpdater::MixfileGitPinUpdater.new(
            dependency_name: dependency.name,
            mixfile_content: content,
            previous_pin: old_pin,
            updated_pin: T.must(replacement_git_pin)
          ).updated_content
        end

        sig { params(content: String).returns(String) }
        def sanitize_mixfile(content)
          Hex::FileUpdater::MixfileSanitizer.new(
            mixfile_content: content
          ).sanitized_content
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def mixfiles
          mixfiles =
            dependency_files
            .select { |f| f.name.end_with?("mix.exs") }
          raise "No mix.exs!" if mixfiles.none?

          mixfiles
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def lockfile
          @lockfile ||= T.let(
            dependency_files.find { |f| f.name == "mix.lock" },
            T.nilable(Dependabot::DependencyFile)
          )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def support_files
          @support_files ||= T.let(
            dependency_files.select(&:support_file),
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { returns(T::Boolean) }
        def wants_prerelease?
          current_version = dependency.version
          if current_version &&
             version_class.correct?(current_version) &&
             version_class.new(current_version).prerelease?
            return true
          end

          dependency.requirements.any? do |req|
            req[:requirement].match?(/\d-[A-Za-z0-9]/)
          end
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end

        sig { returns(Regexp) }
        def version_regex
          Regexp.new(Dependabot::Hex::Version::VERSION_PATTERN)
        end

        sig { params(file_name: String).returns(T::Boolean) }
        def dependency_appears_in_file?(file_name)
          dependency.requirements.any? { |r| r[:file] == file_name }
        end
      end
    end
  end
end
