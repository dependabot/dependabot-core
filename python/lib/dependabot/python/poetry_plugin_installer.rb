# typed: strict
# frozen_string_literal: true

require "shellwords"
require "sorbet-runtime"
require "toml-rb"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/shared_helpers"

module Dependabot
  module Python
    class PoetryPluginInstaller
      extend T::Sig

      # Only allow valid PyPI package names to prevent command injection
      VALID_PLUGIN_NAME = /\A[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?\z/

      # Only allow valid version constraint characters to prevent command injection
      VALID_CONSTRAINT = /\A[a-zA-Z0-9.*,!=<>~^ ]+\z/

      sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).returns(PoetryPluginInstaller) }
      def self.from_dependency_files(dependency_files)
        pyproject_content = dependency_files.find { |f| f.name == "pyproject.toml" }&.content
        new(pyproject_content: pyproject_content)
      end

      sig { params(pyproject_content: T.nilable(String)).void }
      def initialize(pyproject_content:)
        @pyproject_content = T.let(pyproject_content, T.nilable(String))
        @plugins_installed = T.let(false, T::Boolean)
      end

      sig { void }
      def install_required_plugins
        return if @plugins_installed

        required_plugins.each do |name, constraint|
          install_plugin(name, constraint)
        end

        @plugins_installed = true
      end

      private

      sig { returns(T.nilable(String)) }
      attr_reader :pyproject_content

      sig { returns(T::Hash[String, String]) }
      def required_plugins
        return {} unless pyproject_content

        parsed = TomlRB.parse(pyproject_content)
        plugins = parsed.dig("tool", "poetry", "requires-plugins")
        return {} unless plugins.is_a?(Hash)

        plugins.each_with_object({}) do |(name, constraint), result|
          next unless name.is_a?(String) && constraint.is_a?(String)
          next unless valid_plugin_name?(name)
          next unless valid_constraint?(constraint)

          result[name] = constraint
        end
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
        {}
      end

      sig { params(name: String).returns(T::Boolean) }
      def valid_plugin_name?(name)
        VALID_PLUGIN_NAME.match?(name)
      end

      sig { params(constraint: String).returns(T::Boolean) }
      def valid_constraint?(constraint)
        VALID_CONSTRAINT.match?(constraint)
      end

      sig { params(name: String, constraint: String).void }
      def install_plugin(name, constraint)
        Dependabot.logger.info("Installing Poetry plugin: #{name}@#{constraint}")

        escaped = Shellwords.shellescape("#{name}@#{constraint}")
        SharedHelpers.run_shell_command(
          "pyenv exec poetry self add #{escaped}",
          fingerprint: "pyenv exec poetry self add <plugin_name>@<constraint>"
        )
      rescue SharedHelpers::HelperSubprocessFailed => e
        Dependabot.logger.warn(
          "Failed to install Poetry plugin #{name}@#{constraint}: #{e.message}"
        )
      end
    end
  end
end
