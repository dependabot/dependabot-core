# typed: strong
# frozen_string_literal: true

require "toml-rb"
require "sorbet-runtime"
require "pathname"

require "dependabot/uv/file_updater"

module Dependabot
  module Uv
    class FileUpdater < Dependabot::FileUpdaters::Base
      class VersionConfigParser
        extend T::Sig

        ObjectHash = T.type_alias { T::Hash[String, Object] }

        class VersionConfig < T::Struct
          extend T::Sig

          prop :write_paths, T::Array[String], default: []
          prop :source_paths, T::Array[String], default: []
          prop :fallback_version, T.nilable(String), default: nil
          prop :package_name, T.nilable(String), default: nil

          sig { returns(T::Boolean) }
          def dynamic_version?
            write_paths.any? || source_paths.any?
          end
        end

        sig { params(pyproject_content: String, base_path: String, repo_root: String).void }
        def initialize(pyproject_content:, base_path: ".", repo_root: ".")
          @pyproject_content = pyproject_content
          @base_path = base_path
          @repo_root = repo_root
          @parsed_pyproject = T.let(nil, T.nilable(ObjectHash))
        end

        sig { returns(VersionConfig) }
        def parse
          VersionConfig.new(
            write_paths: collect_write_paths,
            source_paths: collect_source_paths,
            fallback_version: extract_fallback_version,
            package_name: extract_package_name
          )
        end

        private

        sig { returns(String) }
        attr_reader :pyproject_content

        sig { returns(String) }
        attr_reader :base_path

        sig { returns(String) }
        attr_reader :repo_root

        sig { returns(ObjectHash) }
        def parsed_pyproject
          return @parsed_pyproject unless @parsed_pyproject.nil?

          @parsed_pyproject = object_hash(T.cast(TomlRB.parse(pyproject_content), Object))
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          @parsed_pyproject = {}
        end

        sig { params(value: Object).returns(ObjectHash) }
        def object_hash(value)
          raise TypeError, "Version configuration must be a table" unless value.is_a?(Hash)

          result = T.let({}, ObjectHash)
          value.each do |raw_key, raw_value|
            key = T.cast(raw_key, Object)
            raise TypeError, "Version configuration keys must be strings" unless key.is_a?(String)

            result[key] = T.cast(raw_value, Object)
          end
          result
        end

        sig { params(path: T::Array[String]).returns(Object) }
        def config_value(path)
          value = T.let(parsed_pyproject, Object)
          path.each do |key|
            return nil if value.nil?

            value = object_hash(value)[key]
          end
          value
        end

        sig { params(path: T::Array[String]).returns(T.nilable(ObjectHash)) }
        def config_table(path)
          value = config_value(path)
          object_hash(value) if value.is_a?(Hash)
        end

        sig { returns(T::Array[String]) }
        def collect_write_paths
          paths = []
          paths += setuptools_scm_write_paths
          paths += hatch_vcs_build_hook_write_paths
          paths.compact.uniq
        end

        sig { returns(T::Array[String]) }
        def collect_source_paths
          paths = []
          paths += hatch_version_source_paths
          paths.compact.uniq
        end

        sig { returns(T::Array[String]) }
        def setuptools_scm_write_paths
          scm_config = config_table(%w(tool setuptools_scm))
          return [] unless scm_config

          paths = []

          version_file = scm_config["version_file"]
          paths << validate_and_resolve_path(version_file) if version_file.is_a?(String)

          write_to = scm_config["write_to"]
          paths << validate_and_resolve_path(write_to) if write_to.is_a?(String)

          paths.compact
        end

        sig { returns(T::Array[String]) }
        def hatch_vcs_build_hook_write_paths
          vcs_hook = config_table(%w(tool hatch build hooks vcs))
          return [] unless vcs_hook

          paths = []

          version_file = vcs_hook["version-file"]
          paths << validate_and_resolve_path(version_file) if version_file.is_a?(String)

          paths.compact
        end

        sig { returns(T::Array[String]) }
        def hatch_version_source_paths
          hatch_version = config_table(%w(tool hatch version))
          return [] unless hatch_version

          paths = []

          version_path = hatch_version["path"]
          paths << validate_and_resolve_path(version_path) if version_path.is_a?(String)

          paths.compact
        end

        sig { returns(T.nilable(String)) }
        def extract_fallback_version
          scm_config = config_table(%w(tool setuptools_scm))
          if scm_config
            fallback = scm_config["fallback_version"]
            return fallback if fallback.is_a?(String)
          end

          raw_options = config_table(%w(tool hatch version raw-options))
          if raw_options
            fallback = raw_options["fallback_version"]
            return fallback if fallback.is_a?(String)
          end

          nil
        end

        sig { returns(T.nilable(String)) }
        def extract_package_name
          name = config_value(%w(project name))
          return name if name.is_a?(String)

          nil
        end

        sig { params(path: String).returns(T.nilable(String)) }
        def validate_and_resolve_path(path)
          return nil if path.empty?
          return nil if Pathname.new(path).absolute?

          resolved = File.expand_path(path, base_path)

          repo_root_expanded = File.expand_path(repo_root)
          resolved_expanded = File.expand_path(resolved)

          unless resolved_expanded.start_with?(repo_root_expanded)
            Dependabot.logger.warn(
              "Version config path '#{path}' resolves outside repository root, ignoring"
            )
            return nil
          end

          Pathname.new(resolved_expanded).relative_path_from(Pathname.new(repo_root_expanded)).to_s
        end
      end
    end
  end
end
