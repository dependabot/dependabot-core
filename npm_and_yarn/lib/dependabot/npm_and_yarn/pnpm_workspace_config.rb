# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "yaml"

require "dependabot/dependency_file"

module Dependabot
  module NpmAndYarn
    # Whether a pnpm workspace keeps a lockfile per project rather than sharing
    # one at its root.
    #
    # pnpm accepts the setting in two files and honours a different spelling in
    # each: `sharedWorkspaceLockfile` in pnpm-workspace.yaml, and
    # `shared-workspace-lockfile` in `.npmrc`. Only what the repository commits
    # is read. The same setting can be supplied by environment variable or on
    # the command line, but that governs the repository's own installs and never
    # reaches ours, so a layout it asks for is one we could not reproduce.
    module PnpmWorkspaceConfig
      extend T::Sig

      # Named here rather than taken from the package-manager classes, which
      # cannot be loaded on their own, so this stays a leaf with no dependency
      # beyond a dependency file.
      WORKSPACE_FILENAME = "pnpm-workspace.yaml"
      NPMRC_FILENAME = ".npmrc"

      WORKSPACE_SETTING = "sharedWorkspaceLockfile"
      NPMRC_SETTING = "shared-workspace-lockfile"

      # Every pnpm version that accepts the setting at all honours it here, so
      # this answer needs no version to go with it.
      sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).returns(T::Boolean) }
      def self.declared_in_workspace_yaml?(dependency_files)
        dependency_files.any? do |file|
          File.basename(file.name) == WORKSPACE_FILENAME && workspace_setting(file.content.to_s) == false
        end
      end

      # pnpm stopped reading non-registry settings from `.npmrc` in 11, so this
      # answer is only true of the pnpm versions that still do. Callers that
      # cannot establish the version should ask `declared_in_workspace_yaml?`
      # instead rather than assume.
      sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).returns(T::Boolean) }
      def self.declared_in_npmrc?(dependency_files)
        dependency_files.any? do |file|
          File.basename(file.name) == NPMRC_FILENAME && npmrc_setting(file.content.to_s) == false
        end
      end

      sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).returns(T::Boolean) }
      def self.lockfile_per_project?(dependency_files)
        declared_in_workspace_yaml?(dependency_files) || declared_in_npmrc?(dependency_files)
      end

      # Parsed as YAML rather than matched line by line, so a flow-style mapping
      # (`{ packages: ['packages/*'], sharedWorkspaceLockfile: false }`) is read
      # rather than missed. An unparseable file reads as unset, which keeps
      # whatever gate the caller would otherwise apply.
      sig { params(content: String).returns(T.nilable(T::Boolean)) }
      def self.workspace_setting(content)
        parsed = T.cast(YAML.safe_load(content, aliases: true), Object)
        return unless parsed.is_a?(Hash)

        boolean(T.cast(parsed[WORKSPACE_SETTING], Object))
      rescue Psych::Exception
        nil
      end

      # `.npmrc` is INI, which has no flow form. The last assignment wins, and
      # both `#` and `;` start a comment.
      sig { params(content: String).returns(T.nilable(T::Boolean)) }
      def self.npmrc_setting(content)
        key = /["']?#{Regexp.escape(NPMRC_SETTING)}["']?/o
        line = content.lines.reverse_each.find { |candidate| candidate.match?(/^\s*#{key}\s*=/) }
        return unless line

        match = line.match(/^\s*#{key}\s*=\s*["']?(\w+)["']?\s*(?:[#;].*)?$/)
        return unless match

        boolean(T.must(match[1]))
      end

      sig { params(value: Object).returns(T.nilable(T::Boolean)) }
      def self.boolean(value)
        return value if value.is_a?(TrueClass) || value.is_a?(FalseClass)
        return unless value.is_a?(String)

        case value.downcase
        when "true" then true
        when "false" then false
        end
      end
      private_class_method :boolean
    end
  end
end
