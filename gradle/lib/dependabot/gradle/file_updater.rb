# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/gradle/file_parser"

module Dependabot
  module Gradle
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/dependency_set_updater"
      require_relative "file_updater/property_value_updater"
      require_relative "file_updater/lockfile_updater"

      SUPPORTED_BUILD_FILE_NAMES = %w(build.gradle build.gradle.kts gradle.lockfile).freeze

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [
          # Matches build.gradle or build.gradle.kts in root directory
          %r{(^|.*/)build\.gradle(\.kts)?$},
          # Matches gradle/libs.versions.toml in root or any subdirectory
          %r{(^|.*/)?gradle/libs\.versions\.toml$},
          # Matches settings.gradle or settings.gradle.kts in root or any subdirectory
          %r{(^|.*/)settings\.gradle(\.kts)?$},
          # Matches dependencies.gradle in root or any subdirectory
          %r{(^|.*/)dependencies\.gradle$},
          %r{(^|.*/)?gradle.lockfile$}
        ]
      end

      sig { override.returns(T::Array[::Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = buildfiles.dup

        # Loop through each of the changed requirements, applying changes to
        # all buildfiles for that change. Note that the logic is different
        # here to other languages because Java has property inheritance across
        # files (although we're not supporting it for gradle yet).
        dependencies.each do |dependency|
          updated_files = update_buildfiles_for_dependency(
            buildfiles: updated_files,
            dependency: dependency
          )
        end

        updated_files = updated_files.reject { |f| buildfiles.include?(f) }

        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      sig { override.void }
      def check_required_files
        raise "No build.gradle or build.gradle.kts!" if dependency_files.empty?
      end

      sig { void }
      def original_file
        dependency_files.find do |f|
          SUPPORTED_BUILD_FILE_NAMES.include?(f.name)
        end
      end

      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      sig do
        params(buildfiles: T::Array[Dependabot::DependencyFile], dependency: Dependabot::Dependency)
          .returns(T::Array[Dependabot::DependencyFile])
      end
      def update_buildfiles_for_dependency(buildfiles:, dependency:)
        files = buildfiles.dup

        # The UpdateChecker ensures the order of requirements is preserved
        # when updating, so we can zip them together in new/old pairs.
        reqs = dependency.requirements.zip(T.must(dependency.previous_requirements))
                         .reject { |new_req, old_req| new_req == old_req }
        # Loop through each changed requirement and update the buildfiles
        reqs.each do |new_req, old_req|
          raise "Bad req match" if old_req.nil? || T.let(new_req[:file], String) != T.let(old_req[:file], String)
          next if T.let(new_req[:requirement], String) == T.let(old_req[:requirement], String)

          buildfile = files.find { |f| f.name == T.let(new_req.fetch(:file), String) }

          # Currently, Dependabot assumes that Gradle projects using Gradle submodules are all in a single
          # repo. However, some projects are actually using git submodule references for the Gradle submodules.
          # When this happens, Dependabot's FileFetcher thinks the Gradle submodules are eligible for update,
          # but then the FileUpdater filters out the git submodule reference from the build file. So we end up
          # with no relevant build file, leaving us with no way to update that dependency.
          # TODO: Figure out a way to actually navigate this rather than throwing an exception.

          raise DependencyFileNotResolvable, "No build file found to update the dependency" if buildfile.nil?

          metadata = T.let(new_req[:metadata], T.nilable(T::Hash[Symbol, T.untyped]))
          if T.let(metadata&.[](:property_name), T.nilable(String))
            files = update_files_for_property_change(files, old_req, new_req)
          elsif T.let(metadata&.[](:dependency_set), T.nilable(T::Hash[Symbol, String]))
            files = update_files_for_dep_set_change(files, old_req, new_req)
          else
            files[T.must(files.index(buildfile))] = update_version_in_buildfile(dependency, buildfile, old_req, new_req)
          end

          next unless Dependabot::Experiments.enabled?(:gradle_lockfile_updater)
          lockfile_updater = LockfileUpdater.new(dependency_files: files)
          lockfiles = lockfile_updater.update_lockfiles(buildfile)
          lockfiles.each do |lockfile|
            existing_file = files.find { |f| f.name == lockfile.name && f.directory == lockfile.directory }
            if existing_file.nil?
              files << lockfile
            else
              files[T.must(files.index(existing_file))] = lockfile
            end
          end
          end
        end

        files
      end
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/AbcSize

      sig do
        params(
          buildfiles: T::Array[Dependabot::DependencyFile],
          old_req: T::Hash[Symbol, T.untyped],
          new_req: T::Hash[Symbol, T.untyped]
        )
          .returns(T::Array[Dependabot::DependencyFile])
      end
      def update_files_for_property_change(buildfiles, old_req, new_req)
        files = buildfiles.dup
        metadata = T.let(new_req.fetch(:metadata), T::Hash[Symbol, T.untyped])
        property_name = T.let(metadata.fetch(:property_name), String)
        file = T.let(new_req.fetch(:file), String)
        buildfile = T.must(files.find { |f| f.name == file })

        PropertyValueUpdater.new(dependency_files: files)
                            .update_files_for_property_change(
                              property_name: property_name,
                              callsite_buildfile: buildfile,
                              previous_value: T.let(old_req.fetch(:requirement), String),
                              updated_value: T.let(new_req.fetch(:requirement), String)
                            )
      end

      sig do
        params(
          buildfiles: T::Array[Dependabot::DependencyFile],
          old_req: T::Hash[Symbol, T.untyped],
          new_req: T::Hash[Symbol, T.untyped]
        )
          .returns(T::Array[Dependabot::DependencyFile])
      end
      def update_files_for_dep_set_change(buildfiles, old_req, new_req)
        files = buildfiles.dup
        metadata = T.let(new_req.fetch(:metadata), T::Hash[Symbol, T.untyped])
        dependency_set = T.let(metadata.fetch(:dependency_set), T::Hash[Symbol, String])
        buildfile = T.must(files.find { |f| f.name == T.let(new_req.fetch(:file), String) })

        DependencySetUpdater.new(dependency_files: files)
                            .update_files_for_dep_set_change(
                              dependency_set: dependency_set,
                              buildfile: buildfile,
                              previous_requirement: T.let(old_req.fetch(:requirement), String),
                              updated_requirement: T.let(new_req.fetch(:requirement), String)
                            )
      end

      sig do
        params(
          dependency: Dependabot::Dependency,
          buildfile: Dependabot::DependencyFile,
          previous_req: T::Hash[Symbol, T.untyped],
          requirement: T::Hash[Symbol, T.untyped]
        )
          .returns(Dependabot::DependencyFile)
      end
      def update_version_in_buildfile(dependency, buildfile, previous_req,
                                      requirement)
        original_content = T.must(buildfile.content.dup)

        updated_content =
          original_buildfile_declarations(dependency, previous_req).reduce(original_content) do |content, declaration|
            content.gsub(
              declaration,
              updated_buildfile_declaration(declaration, previous_req, requirement)
            )
          end

        raise "Expected content to change!" if updated_content == buildfile.content

        updated_file(file: buildfile, content: updated_content)
      end

      # rubocop:disable Metrics/AbcSize
      sig do
        params(
          dependency: Dependabot::Dependency,
          requirement: T::Hash[Symbol, T.untyped]
        ).returns(T::Array[String])
      end
      def original_buildfile_declarations(dependency, requirement)
        # This implementation is limited to declarations that appear on a
        # single line.
        buildfile = T.must(buildfiles.find { |f| f.name == T.let(requirement.fetch(:file), String) })

        T.must(buildfile.content).lines.select do |line|
          line = evaluate_properties(line, buildfile)
          line = line.gsub(%r{(?<=^|\s)//.*$}, "")

          if dependency.name.include?(":")
            dep_parts = dependency.name.split(":")
            next false unless line.include?(T.must(dep_parts.first)) || line.include?(T.must(dep_parts.last))
          elsif T.let(requirement.fetch(:file), String).end_with?(".toml")
            next false unless line.include?(dependency.name)
          else
            name_regex_value = /['"]#{Regexp.quote(dependency.name)}['"]/
            name_regex = /(id|kotlin)(\s+#{name_regex_value}|\(#{name_regex_value}\))/
            next false unless line.match?(name_regex)
          end

          line.include?(T.let(requirement.fetch(:requirement), String))
        end
      end
      # rubocop:enable Metrics/AbcSize

      sig { params(string: String, buildfile: Dependabot::DependencyFile).returns(String) }
      def evaluate_properties(string, buildfile)
        result = string.dup

        string.scan(Gradle::FileParser::PROPERTY_REGEX) do
          prop_name = T.must(Regexp.last_match).named_captures.fetch("property_name")
          property_value = T.let(
            property_value_finder.property_value(property_name: prop_name, callsite_buildfile: buildfile),
            T.nilable(String)
          )
          next unless property_value

          result.sub!(Regexp.last_match.to_s, property_value)
        end

        result
      end

      sig { returns(Gradle::FileParser::PropertyValueFinder) }
      def property_value_finder
        @property_value_finder ||= T.let(
          Gradle::FileParser::PropertyValueFinder.new(dependency_files: dependency_files),
          T.nilable(Gradle::FileParser::PropertyValueFinder)
        )
      end

      sig do
        params(
          original_buildfile_declaration: String,
          previous_req: T::Hash[Symbol, T.untyped],
          requirement: T::Hash[Symbol, T.untyped]
        ).returns(String)
      end
      def updated_buildfile_declaration(original_buildfile_declaration, previous_req, requirement)
        original_req_string = T.let(previous_req.fetch(:requirement), String)
        new_req_string = T.let(requirement.fetch(:requirement), String)

        original_buildfile_declaration.gsub(original_req_string, new_req_string)
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def buildfiles
        @buildfiles ||= T.let(dependency_files.reject(&:support_file?), T.nilable(T::Array[Dependabot::DependencyFile]))
      end
    end
  end
end

Dependabot::FileUpdaters.register("gradle", Dependabot::Gradle::FileUpdater)
