# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "sorbet-runtime"

module Dependabot
  module Bun
    module Helpers
      extend T::Sig

      # BUN Version Constants
      BUN_V1 = 1
      BUN_DEFAULT_VERSION = BUN_V1

      sig { params(_bun_lock: T.nilable(DependencyFile)).returns(Integer) }
      def self.bun_version_numeric(_bun_lock)
        BUN_DEFAULT_VERSION
      end

      sig { returns(T.nilable(String)) }
      def self.node_version
        version = run_node_command("-v", fingerprint: "-v").strip

        # Validate the output format (e.g., "v20.18.1" or "20.18.1")
        if version.match?(/^v?\d+(\.\d+){2}$/)
          version.strip.delete_prefix("v") # Remove the "v" prefix if present
        end
      rescue StandardError => e
        Dependabot.logger.error("Error retrieving Node.js version: #{e.message}")
        nil
      end

      sig { params(command: String, fingerprint: T.nilable(String)).returns(String) }
      def self.run_node_command(command, fingerprint: nil)
        full_command = "node #{command}"

        Dependabot.logger.info("Running node command: #{full_command}")

        result = Dependabot::SharedHelpers.run_shell_command(
          full_command,
          fingerprint: "node #{fingerprint || command}"
        )

        Dependabot.logger.info("Command executed successfully: #{full_command}")
        result
      rescue StandardError => e
        Dependabot.logger.error("Error running node command: #{full_command}, Error: #{e.message}")
        raise
      end

      sig { returns(T.nilable(String)) }
      def self.bun_version
        version = run_bun_command("--version", fingerprint: "--version").strip
        if version.include?("+")
          version.split("+").first # Remove build info, if present
        end
      rescue StandardError => e
        Dependabot.logger.error("Error retrieving Bun version: #{e.message}")
        nil
      end

      sig { params(command: T.any(String, T::Array[String]), fingerprint: T.nilable(String)).returns(String) }
      def self.run_bun_command(command, fingerprint: nil)
        full_command = command.is_a?(Array) ? ["bun", *command] : "bun #{command}"
        display_command = full_command.is_a?(Array) ? full_command.join(" ") : full_command
        fingerprint_command = command.is_a?(Array) ? command.join(" ") : command

        Dependabot.logger.info("Running bun command: #{display_command}")

        result = Dependabot::SharedHelpers.run_shell_command(
          full_command,
          fingerprint: "bun #{fingerprint || fingerprint_command}"
        )

        Dependabot.logger.info("Command executed successfully: #{display_command}")
        result
      rescue StandardError => e
        Dependabot.logger.error("Error running bun command: #{display_command}, Error: #{e.message}")
        raise
      end

      BUNFIG_FILE = "bunfig.toml"
      FROZEN_LOCKFILE_PATH = %w(install frozenLockfile).freeze
      TOML_KEY_SEGMENT = /"(?:[^"\\\n]|\\.)*"|'[^'\n]*'|[A-Za-z0-9_-]+/
      TOML_KEY_PATH = /#{TOML_KEY_SEGMENT}(?:[ \t]*\.[ \t]*#{TOML_KEY_SEGMENT})*/
      TOML_TABLE_HEADER = /\A[ \t]*(?<array>\[)?\[[ \t]*(?<path>#{TOML_KEY_PATH})[ \t]*\]\]?[ \t]*(?:#.*)?\z/
      FROZEN_LOCKFILE_SETTING = /\A(?<before>[ \t]*(?<path>#{TOML_KEY_PATH})[ \t]*=[ \t]*)true\b/
      TOML_ESCAPES = T.let(
        {
          "b" => "\b", "t" => "\t", "n" => "\n", "f" => "\f", "r" => "\r", "e" => "\e", '"' => '"', "\\" => "\\"
        }.freeze,
        T::Hash[String, String]
      )

      # A repository can set `frozenLockfile = true` in its bunfig.toml so that a plain `bun install` never rewrites
      # bun.lock. Bun has no flag to undo that, and refuses any install or update that would change the lockfile, which
      # is the whole job here. Runs the block with the setting turned off in the bunfig.toml of the current directory,
      # then puts the file back as it was.
      sig do
        type_parameters(:T)
          .params(_block: T.proc.returns(T.type_parameter(:T)))
          .returns(T.type_parameter(:T))
      end
      def self.with_lockfile_changes_allowed(&_block)
        original = File.read(BUNFIG_FILE) if File.file?(BUNFIG_FILE)
        thawed = original && without_frozen_lockfile(original)
        return yield if thawed.nil? || thawed == original

        File.write(BUNFIG_FILE, thawed)
        begin
          yield
        ensure
          File.write(BUNFIG_FILE, original)
        end
      end

      # Only the key `install.frozenLockfile` is the setting bun reads, however TOML spells it: under an `[install]`
      # table, as a dotted key, with quoted names or with spaces around the dots. A key of that name in another table is
      # left alone, and so is everything else in the file.
      sig { params(bunfig: String).returns(String) }
      def self.without_frozen_lockfile(bunfig)
        table = T.let([], T::Array[String])

        bunfig.lines.map do |line|
          if (header = line.chomp.match(TOML_TABLE_HEADER))
            table = header[:array] ? ["[[#{header[:path]}]]"] : toml_key_path(T.must(header[:path]))
            next line
          end

          setting = line.match(FROZEN_LOCKFILE_SETTING)
          next line unless setting && table + toml_key_path(T.must(setting[:path])) == FROZEN_LOCKFILE_PATH

          line.sub(FROZEN_LOCKFILE_SETTING, "\\k<before>false")
        end.join
      end

      # Splits a TOML key such as `"install" . frozenLockfile` into its unquoted names.
      sig { params(key: String).returns(T::Array[String]) }
      def self.toml_key_path(key)
        T.cast(key.scan(TOML_KEY_SEGMENT), T::Array[String]).map do |segment|
          if segment.start_with?('"')
            segment[1..-2].to_s.gsub(/\\(?:u(\h{4})|U(\h{8})|(.))/) do
              hex = Regexp.last_match(1) || Regexp.last_match(2)
              hex ? [hex.hex].pack("U") : TOML_ESCAPES.fetch(Regexp.last_match(3).to_s, Regexp.last_match(3).to_s)
            end
          else
            segment.delete_prefix("'").delete_suffix("'")
          end
        end
      end

      sig { params(dependency_set: Dependabot::FileParsers::Base::DependencySet).returns(T::Array[Dependency]) }
      def self.dependencies_with_all_versions_metadata(dependency_set)
        dependency_set.dependencies.map do |dependency|
          dependency.metadata[:all_versions] = dependency_set.all_versions_for_name(dependency.name)
          dependency
        end
      end
    end
  end
end
