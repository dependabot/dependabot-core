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
      require_relative "file_updater/wrapper_updater"

      SUPPORTED_BUILD_FILE_NAMES = %w(build.gradle build.gradle.kts gradle.lockfile).freeze

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
      # rubocop:disable Metrics/PerceivedComplexity
      sig do
        params(buildfiles: T::Array[Dependabot::DependencyFile], dependency: Dependabot::Dependency)
          .returns(T::Array[Dependabot::DependencyFile])
      end
      def update_buildfiles_for_dependency(buildfiles:, dependency:)
        files = buildfiles.dup

        # dependencies may have multiple requirements targeting the same file or build dir
        # we keep the last one by path to later run its native helpers
        buildfiles_processed = T.let({}, T::Hash[String, Dependabot::DependencyFile])

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

          metadata = symbol_object_hash(T.cast(new_req[:metadata], T.nilable(Object)))
          if metadata && metadata[:property_name].is_a?(String)
            files = update_files_for_property_change(files, old_req, new_req)
          elsif metadata && symbol_object_hash(metadata[:dependency_set])
            files = update_files_for_dep_set_change(files, old_req, new_req)
          else
            files[T.must(files.index(buildfile))] = update_version_in_buildfile(dependency, buildfile, old_req, new_req)
          end

          buildfiles_processed[buildfile.name] = buildfile
        end

        # runs native updaters (e.g. wrapper, lockfile) on relevant build files updated
        buildfiles_processed.each_value do |buildfile|
          wrapper_updater = WrapperUpdater.new(dependency_files: files, dependency: dependency)
          updated_files = wrapper_updater.update_files(buildfile)
          replace_updated_files(files, updated_files)
        end
        if Dependabot::Experiments.enabled?(:gradle_lockfile_updater)
          update_lockfiles_for_buildfiles(files, buildfiles_processed)
        end

        files
      end
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/AbcSize

      sig do
        params(
          files: T::Array[Dependabot::DependencyFile],
          buildfiles_processed: T::Hash[String, Dependabot::DependencyFile]
        ).void
      end
      def update_lockfiles_for_buildfiles(files, buildfiles_processed)
        lockfile_roots_processed = T.let(Set.new, T::Set[String])

        buildfiles_processed.each_value do |buildfile|
          lockfile_updater = LockfileUpdater.new(dependency_files: files)
          root_dir = lockfile_updater.determine_root_dir(build_file: buildfile)
          next if lockfile_roots_processed.include?(root_dir)

          lockfile_roots_processed.add(root_dir)

          updated_files = lockfile_updater.update_lockfiles(buildfile)
          replace_updated_files(files, updated_files)
        end
      end
      sig do
        params(
          files: T::Array[Dependabot::DependencyFile],
          updated_files: T::Array[Dependabot::DependencyFile]
        ).returns(T::Array[Dependabot::DependencyFile])
      end
      def replace_updated_files(files, updated_files)
        updated_files.each do |file|
          existing_file = files.find { |f| f.name == file.name }
          if existing_file.nil?
            files << file
          else
            files[T.must(files.index(existing_file))] = file
          end
        end
        files
      end

      sig do
        params(
          buildfiles: T::Array[Dependabot::DependencyFile],
          old_req: T::Hash[Symbol, Object],
          new_req: T::Hash[Symbol, Object]
        )
          .returns(T::Array[Dependabot::DependencyFile])
      end
      def update_files_for_property_change(buildfiles, old_req, new_req)
        files = buildfiles.dup
        metadata = symbol_object_hash_value(new_req, :metadata)
        property_name = string_value(metadata, :property_name)
        file = string_value(new_req, :file)
        buildfile = T.must(files.find { |f| f.name == file })

        PropertyValueUpdater.new(dependency_files: files)
                            .update_files_for_property_change(
                              property_name: property_name,
                              callsite_buildfile: buildfile,
                              previous_value: string_value(old_req, :requirement),
                              updated_value: string_value(new_req, :requirement)
                            )
      end

      sig do
        params(
          buildfiles: T::Array[Dependabot::DependencyFile],
          old_req: T::Hash[Symbol, Object],
          new_req: T::Hash[Symbol, Object]
        )
          .returns(T::Array[Dependabot::DependencyFile])
      end
      def update_files_for_dep_set_change(buildfiles, old_req, new_req)
        files = buildfiles.dup
        metadata = symbol_object_hash_value(new_req, :metadata)
        dependency_set = symbol_string_hash_value(metadata, :dependency_set)
        buildfile = T.must(files.find { |f| f.name == string_value(new_req, :file) })

        DependencySetUpdater.new(dependency_files: files)
                            .update_files_for_dep_set_change(
                              dependency_set: dependency_set,
                              buildfile: buildfile,
                              previous_requirement: string_value(old_req, :requirement),
                              updated_requirement: string_value(new_req, :requirement)
                            )
      end

      sig do
        params(
          dependency: Dependabot::Dependency,
          buildfile: Dependabot::DependencyFile,
          previous_req: T::Hash[Symbol, Object],
          requirement: T::Hash[Symbol, Object]
        )
          .returns(Dependabot::DependencyFile)
      end
      def update_version_in_buildfile(
        dependency,
        buildfile,
        previous_req,
        requirement
      )
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
      # rubocop:disable Metrics/PerceivedComplexity
      sig do
        params(
          dependency: Dependabot::Dependency,
          requirement: T::Hash[Symbol, Object]
        ).returns(T::Array[String])
      end
      def original_buildfile_declarations(dependency, requirement)
        # This implementation is limited to declarations that appear on a
        # single line.
        file = string_value(requirement, :file)
        buildfile = T.must(buildfiles.find { |f| f.name == file })

        T.must(buildfile.content).lines.select do |line|
          line = evaluate_properties(line, buildfile)
          line = line.gsub(%r{(?<=^|\s)//.*$}, "")

          if dependency.name.include?(":")
            dep_parts = dependency.name.split(":")
            next false unless line.include?(T.must(dep_parts.first)) || line.include?(T.must(dep_parts.last))
          elsif file.end_with?(".properties")
            source = requirement[:source]
            property = T.let(nil, T.nilable(String))
            source_hash = symbol_object_hash(source)
            source_property = source_hash&.[](:property)
            property = source_property if source_property.is_a?(String)
            next false unless property && line.start_with?(property)
          elsif file.end_with?(".toml")
            next false unless line.include?(dependency.name)
          else
            name_regex_value = /['"]#{Regexp.quote(dependency.name)}['"]/
            name_regex = /(id|kotlin)(\s+#{name_regex_value}|\(#{name_regex_value}\))/
            next false unless line.match?(name_regex)
          end

          line.include?(string_value(requirement, :requirement))
        end
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/PerceivedComplexity

      sig { params(string: String, buildfile: Dependabot::DependencyFile).returns(String) }
      def evaluate_properties(string, buildfile)
        result = string.dup

        string.scan(Gradle::FileParser::PROPERTY_REGEX) do
          prop_name = T.must(T.must(Regexp.last_match).named_captures.fetch("property_name"))
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
          previous_req: T::Hash[Symbol, Object],
          requirement: T::Hash[Symbol, Object]
        ).returns(String)
      end
      def updated_buildfile_declaration(original_buildfile_declaration, previous_req, requirement)
        original_req_string = string_value(previous_req, :requirement)
        new_req_string = string_value(requirement, :requirement)

        original_buildfile_declaration.gsub(original_req_string, new_req_string)
      end

      sig { params(hash: T::Hash[Symbol, Object], key: Symbol).returns(String) }
      def string_value(hash, key)
        value = hash.fetch(key)
        raise TypeError, "Expected #{key} to be a String" unless value.is_a?(String)

        value
      end

      sig { params(hash: T::Hash[Symbol, Object], key: Symbol).returns(T::Hash[Symbol, Object]) }
      def symbol_object_hash_value(hash, key)
        value = hash.fetch(key)
        raise TypeError, "Expected #{key} to be a Hash" unless value.is_a?(Hash)

        value
      end

      sig { params(hash: T::Hash[Symbol, Object], key: Symbol).returns(T::Hash[Symbol, String]) }
      def symbol_string_hash_value(hash, key)
        value = hash.fetch(key)
        raise TypeError, "Expected #{key} to be a Hash" unless value.is_a?(Hash)

        result = T.let({}, T::Hash[Symbol, String])
        value.each_pair do |hash_key_object, hash_value_object|
          hash_key = T.cast(hash_key_object, T.nilable(Object))
          hash_value = T.cast(hash_value_object, T.nilable(Object))
          raise TypeError, "Expected #{key} keys and values to be Symbols and Strings" unless hash_key.is_a?(Symbol) &&
                                                                                              hash_value.is_a?(String)

          result[hash_key] = hash_value
        end
        result
      end

      sig { params(value: T.nilable(Object)).returns(T.nilable(T::Hash[Symbol, Object])) }
      def symbol_object_hash(value)
        return unless value.is_a?(Hash)

        value
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def buildfiles
        @buildfiles ||= T.let(dependency_files.reject(&:support_file?), T.nilable(T::Array[Dependabot::DependencyFile]))
      end
    end
  end
end

Dependabot::FileUpdaters.register("gradle", Dependabot::Gradle::FileUpdater)
