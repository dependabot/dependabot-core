# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/kotlin_toolchain/constants"
require "dependabot/kotlin_toolchain/yaml_parser"

module Dependabot
  module KotlinToolchain
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/catalog_editor"
      require_relative "file_updater/wrapper_updater"
      require_relative "file_updater/yaml_editor"

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        contents = dependency_files.to_h { |file| [file.name, file.content.to_s] }

        dependencies.reject { |dependency| wrapper_dependency?(dependency) }.each do |dependency|
          contents = apply_dependency_update(contents, dependency)
        end

        wrapper_dependency = dependencies.find { |dependency| wrapper_dependency?(dependency) }
        wrapper_updates = wrapper_dependency ? update_wrappers(wrapper_dependency) : []
        wrapper_updates.each { |file| contents[file.name] = file.content.to_s }

        updated = dependency_files.filter_map do |file|
          content = contents.fetch(file.name)
          next if content == file.content.to_s

          validate_content!(file.name, content)
          updated_file(file: file, content: content)
        end

        raise "No files changed!" if updated.empty?

        updated
      end

      private

      sig { override.void }
      def check_required_files
        wrappers = dependency_files.select { |file| WRAPPER_FILES.include?(File.basename(file.name)) }
        raise "Kotlin Toolchain wrapper is missing" if wrappers.empty?
      end

      sig do
        params(
          contents: T::Hash[String, String],
          dependency: Dependabot::Dependency
        ).returns(T::Hash[String, String])
      end
      def apply_dependency_update(contents, dependency)
        previous_requirements = dependency.previous_requirements
        raise "Previous requirements are required to update #{dependency.name}" unless previous_requirements

        dependency.requirements.zip(previous_requirements).each do |new_requirement, old_requirement|
          next unless old_requirement
          next if new_requirement[:requirement] == old_requirement[:requirement]

          filename = T.cast(new_requirement[:file], String)
          metadata = new_requirement[:metadata] || old_requirement[:metadata]
          unless metadata.is_a?(Hash)
            raise Dependabot::DependencyFileNotResolvable,
                  "Missing source metadata for #{dependency.name} in #{filename}"
          end

          previous_version = T.cast(old_requirement[:requirement], String)
          new_version = T.cast(new_requirement[:requirement], String)
          contents[filename] = update_content(
            content: contents.fetch(filename),
            filename: filename,
            metadata: metadata,
            previous_version: previous_version,
            new_version: new_version
          )
        end

        contents
      end

      sig do
        params(
          content: String,
          filename: String,
          metadata: T::Hash[T.any(Symbol, String), Object],
          previous_version: String,
          new_version: String
        ).returns(String)
      end
      def update_content(content:, filename:, metadata:, previous_version:, new_version:)
        kind = metadata_value(metadata, :kind)
        case kind
        when "yaml_value", "yaml_key"
          update_yaml(
            content: content,
            filename: filename,
            metadata: metadata,
            previous_version: previous_version,
            new_version: new_version,
            key: kind == "yaml_key"
          )
        when "catalog_version"
          CatalogEditor.new(content: content, filename: filename).replace_version_key(
            key: metadata_value(metadata, :version_key),
            previous_version: previous_version,
            new_version: new_version
          )
        when "catalog_inline"
          CatalogEditor.new(content: content, filename: filename).replace_inline_version(
            alias_name: metadata_value(metadata, :alias),
            previous_version: previous_version,
            new_version: new_version
          )
        else
          raise Dependabot::DependencyFileNotResolvable,
                "Unsupported Kotlin Toolchain declaration #{kind.inspect} in #{filename}"
        end
      end

      sig do
        params(
          content: String,
          filename: String,
          metadata: T::Hash[T.any(Symbol, String), Object],
          previous_version: String,
          new_version: String,
          key: T::Boolean
        ).returns(String)
      end
      def update_yaml(content:, filename:, metadata:, previous_version:, new_version:, key:)
        raw_path = metadata[:path] || metadata["path"]
        raise Dependabot::DependencyFileNotResolvable, "Missing YAML path in #{filename}" unless raw_path.is_a?(Array)

        path = raw_path

        original_value = metadata_value(metadata, :value)
        coordinate = metadata[:coordinate] || metadata["coordinate"]
        value = if coordinate.is_a?(String)
                  updated_coordinate_value(
                    original_value,
                    coordinate: coordinate,
                    previous_version: previous_version,
                    new_version: new_version
                  )
                else
                  new_version
                end

        YamlEditor.new(content: content, filename: filename).replace(
          path: path,
          value: value,
          key: key
        )
      end

      sig do
        params(
          original_value: String,
          coordinate: String,
          previous_version: String,
          new_version: String
        ).returns(String)
      end
      def updated_coordinate_value(original_value, coordinate:, previous_version:, new_version:)
        updated_coordinate = coordinate.sub(/:#{Regexp.escape(previous_version)}\z/, ":#{new_version}")
        unless updated_coordinate != coordinate && original_value.include?(coordinate)
          raise Dependabot::DependencyFileNotResolvable,
                "Unable to update #{coordinate} from #{previous_version}"
        end

        original_value.sub(coordinate, updated_coordinate)
      end

      sig { params(dependency: Dependabot::Dependency).returns(T::Array[Dependabot::DependencyFile]) }
      def update_wrappers(dependency)
        WrapperUpdater.new(
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials
        ).updated_files
      end

      sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
      def wrapper_dependency?(dependency)
        dependency.name == WRAPPER_DEPENDENCY_NAME || dependency.metadata[:wrapper] == true
      end

      sig { params(filename: String, content: String).void }
      def validate_content!(filename, content)
        if filename.end_with?(".yaml", ".yml")
          YamlParser.load(content, filename: filename)
        elsif filename.end_with?(".toml")
          TomlRB.parse(content)
        end
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError => e
        raise Dependabot::DependencyFileNotParseable.new(filename, "#{filename}: #{e.message}")
      end

      sig { params(metadata: T::Hash[T.any(Symbol, String), Object], key: Symbol).returns(String) }
      def metadata_value(metadata, key)
        value = metadata[key] || metadata[key.to_s]
        return value if value.is_a?(String)

        raise Dependabot::DependencyFileNotResolvable, "Missing #{key} metadata"
      end
    end
  end
end

Dependabot::FileUpdaters.register(
  "kotlin_toolchain",
  Dependabot::KotlinToolchain::FileUpdater
)
