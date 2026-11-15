# typed: strong
# frozen_string_literal: true

require "toml-rb"

require "dependabot/errors"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Mise
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      CONF_D_DIRECTORIES = %w(.config/mise/conf.d .mise/conf.d mise/conf.d).freeze
      CONFIG_DIRECTORIES = T.let(
        (%w(. .config .config/mise .mise mise) + CONF_D_DIRECTORIES).freeze,
        T::Array[String]
      )
      # Project config locations from mise's SHARED_CONFIG_FILENAMES and
      # env_config_patterns (src/config/mod.rs); keep them in sync on mise bumps.
      CONFIG_FILE_PATTERNS = T.let(
        [
          %r{\A(?:\.config/mise|\.?mise)(?:\.[a-zA-Z0-9_-]+)?(?:\.local)?\.toml\z},
          %r{\A(?:\.config/mise|\.?mise)/config(?:\.[a-zA-Z0-9_-]+)?(?:\.local)?\.toml\z},
          %r{\A\.config/mise/mise(?:\.local)?\.toml\z},
          %r{\A(?:\.config/mise|\.?mise)/conf\.d/[^./][^/]*\.toml\z},
          %r{\A(?:\.config/mise|\.?mise)/conf\.d/[^./][^/]*/mise(?:\.[a-zA-Z0-9_-]+)?(?:\.local)?\.toml\z}
        ].freeze,
        T::Array[Regexp]
      )

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
        CONFIG_FILE_PATTERNS.any? { |pattern| filename.match?(pattern) }
      end

      # The npm (aube) and Python (uv) dependency graphs mise records, e.g.
      # `aube = { path = "locks/npm-prettier/3.3.0", digest = "..." }`, relative to the lockfile.
      SIDECAR_KINDS = %w(aube uv).freeze

      sig { params(lockfile_name: String, content: String).returns(T::Array[String]) }
      def self.sidecar_dirs(lockfile_name, content)
        tools = T.cast(TomlRB.parse(content), T::Hash[String, Object])["tools"]
        return [] unless tools.is_a?(Hash)

        paths = tools.values.flatten.grep(Hash).flat_map do |entry|
          SIDECAR_KINDS.filter_map do |kind|
            graph = T.let(entry[kind], Object)
            path = graph.is_a?(Hash) ? T.let(graph["path"], Object) : nil
            path if path.is_a?(String) && !path.start_with?("/") && !path.split("/").include?("..")
          end
        end
        paths.uniq.map { |path| File.join(File.dirname(lockfile_name), path).delete_prefix("./") }
      end

      # Mirrors lockfile_path_for_config and the env and local helpers in mise's src/lockfile.rs.
      sig { params(config_path: String).returns(String) }
      def self.lockfile_path_for(config_path)
        filename = File.basename(config_path)
        env = filename[/\A(?:\.?mise|config)\.([^.]+)(?:\.local)?\.toml\z/, 1]
        local = filename.include?(".local.")
        name = ["mise", (env unless env == "local"), ("local" if local), "lock"].compact.join(".")

        dir = File.dirname(config_path)
        if File.basename(dir) == "conf.d"
          dir = File.dirname(dir)
        elsif File.basename(File.dirname(dir)) == "conf.d"
          dir = File.dirname(dir, 2)
        end
        File.join(dir, name).delete_prefix("./")
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

        return fetched_files + lockfiles_for(fetched_files) unless fetched_files.empty?

        raise Dependabot::DependencyFileNotFound.new(nil, self.class.required_files_message)
      end

      private

      sig { params(config_files: T::Array[DependencyFile]).returns(T::Array[DependencyFile]) }
      def lockfiles_for(config_files)
        lockfiles = config_files.map { |file| self.class.lockfile_path_for(file.name) }.uniq
                                .filter_map { |path| fetch_file_if_present(path) }
        lockfiles + lockfiles.flat_map { |lockfile| sidecar_dirs_for(lockfile) }.uniq.flat_map { |dir| files_in(dir) }
      end

      sig { params(lockfile: DependencyFile).returns(T::Array[String]) }
      def sidecar_dirs_for(lockfile)
        self.class.sidecar_dirs(lockfile.name, lockfile.content.to_s)
      rescue TomlRB::Error => e
        raise Dependabot::DependencyFileNotParseable.new(lockfile.name, e.message)
      end

      sig { params(dir: String).returns(T::Array[DependencyFile]) }
      def files_in(dir)
        repo_contents(dir: dir, raise_errors: false).flat_map do |entry|
          path = File.join(dir, entry.name)
          case entry.type
          when "file" then [fetch_file_from_host(path)]
          when "dir" then files_in(path)
          else []
          end
        end
      end

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
