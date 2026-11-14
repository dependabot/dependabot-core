# typed: strong
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Mise
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      # Project config locations from mise's SHARED_CONFIG_FILENAMES and
      # env_config_patterns (src/config/mod.rs); keep them in sync on mise bumps.
      CONF_D_DIRECTORIES = %w(.config/mise/conf.d .mise/conf.d mise/conf.d).freeze
      CONFIG_DIRECTORIES = T.let(
        (%w(. .config .config/mise .mise mise) + CONF_D_DIRECTORIES).freeze,
        T::Array[String]
      )
      # conf.d folders read only mise.toml, mise.local.toml, mise.<env>.toml and mise.<env>.local.toml.
      CONF_D_FOLDER_FILE = %r{
        \A(?:\.config/mise|\.?mise)/conf\.d/[^./][^/]*/
        mise(?:\.[a-zA-Z0-9_-]+)?(?:\.local)?\.toml\z
      }x

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a mise TOML configuration file " \
          "(for example, mise.toml or .config/mise/config.toml)."
      end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |filename| mise_config_file?(filename) }
      end

      sig { params(filename: String).returns(T::Boolean) }
      def self.mise_config_file?(filename)
        filename.match?(%r{\A(?:\.?mise|\.config/mise)(?:\.[a-zA-Z0-9_-]+)?(?:\.local)?\.toml\z}) ||
          filename.match?(%r{\A(?:\.config/mise|\.?mise)/config(?:\.[a-zA-Z0-9_-]+)?(?:\.local)?\.toml\z}) ||
          %w(.config/mise/mise.toml .config/mise/mise.local.toml).include?(filename) ||
          filename.match?(%r{\A(?:\.config/mise|\.?mise)/conf\.d/[^./][^/]*\.toml\z}) ||
          filename.match?(CONF_D_FOLDER_FILE)
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        unless allow_beta_ecosystems?
          raise Dependabot::DependencyFileNotFound.new(
            nil,
            "Mise support is currently in beta. Set ALLOW_BETA_ECOSYSTEMS=true to enable it."
          )
        end

        fetched_files = config_directories.flat_map do |dir|
          repo_contents(dir: dir, raise_errors: false).filter_map do |file|
            next unless file.type == "file"

            path = File.join(dir, file.name).delete_prefix("./")
            next unless self.class.mise_config_file?(path)

            fetch_file_from_host(path)
          end
        end

        return fetched_files unless fetched_files.empty?

        raise Dependabot::DependencyFileNotFound.new(
          "mise.toml",
          "No mise configuration file found"
        )
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.anything])) }
      def ecosystem_versions
        nil
      end

      private

      sig { returns(T::Array[String]) }
      def config_directories
        conf_d_folders = CONF_D_DIRECTORIES.flat_map do |dir|
          repo_contents(dir: dir, raise_errors: false)
            .select { |entry| entry.type == "dir" && !entry.name.start_with?(".") }
            .map { |entry| File.join(dir, entry.name) }
        end

        CONFIG_DIRECTORIES + conf_d_folders
      end
    end
  end
end

Dependabot::FileFetchers.register("mise", Dependabot::Mise::FileFetcher)
