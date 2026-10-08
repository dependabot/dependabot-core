# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "json"
require "pathname"
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

      MANIFEST_FILENAME = "package.json"

      WORKSPACE_SETTING = "sharedWorkspaceLockfile"
      NPMRC_SETTING = "shared-workspace-lockfile"

      # pnpm stopped taking non-registry settings from `.npmrc` in 11.
      NPMRC_SETTINGS_DROPPED_MAJOR = 11

      # Whether the repository asks for a lockfile per project.
      #
      # pnpm resolves the two files by precedence, not by either one winning on
      # a particular value: where pnpm-workspace.yaml states the setting it is
      # used, and `.npmrc` is consulted only when it does not. Measured on pnpm
      # 10.34.5, on the cases that actually tell precedence apart from the
      # default — `sharedWorkspaceLockfile: true` alongside
      # `shared-workspace-lockfile=false` produces one shared lockfile, and
      # `sharedWorkspaceLockfile: false` alongside `shared-workspace-lockfile=true`
      # produces one per project.
      #
      # Answered from the dependency files and nothing else, so that every stage
      # asking it gets the same answer. A caller-supplied knob here is what let
      # the fetcher and the updater disagree about the same repository.
      sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).returns(T::Boolean) }
      def self.lockfile_per_project?(dependency_files)
        setting(dependency_files) == DISABLED
      end

      DISABLED = :disabled
      ENABLED = :enabled
      # The key is there but holds something pnpm reads as a string.
      OTHER = :other

      # What the repository states, or nil where it states nothing.
      sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).returns(T.nilable(Symbol)) }
      def self.setting(dependency_files)
        root = workspace_root_dir(dependency_files)
        stated = stated_at(dependency_files, root, WORKSPACE_FILENAME) { |c| workspace_setting(c) }
        return stated unless stated.nil?
        return nil unless npmrc_read_by_pnpm?(dependency_files, root)

        stated_at(dependency_files, root, NPMRC_FILENAME) { |c| npmrc_setting(c) }
      end

      # Whether the pnpm this repository runs still takes the setting from
      # `.npmrc`. It stopped in 11, so the spelling can only be acted on where
      # the repository says which pnpm runs, and `packageManager` is the one
      # statement of that which is exact. A version guessed from the lockfile will
      # not do: pnpm 10, 11 and 12 all write lockfileVersion 9.0, so the guess
      # resolves every one of them to 10, and `PackageManagerHelper#setup` only
      # caches what it resolves rather than activating it.
      sig { params(dependency_files: T::Array[Dependabot::DependencyFile], root: String).returns(T::Boolean) }
      def self.npmrc_read_by_pnpm?(dependency_files, root)
        pinned = package_manager_pin(dependency_files, root)
        return false unless pinned

        major = pinned[/\Apnpm@(\d+)/, 1]
        !major.nil? && major.to_i < NPMRC_SETTINGS_DROPPED_MAJOR
      end
      private_class_method :npmrc_read_by_pnpm?

      # The `packageManager` the workspace root declares, or nil.
      sig { params(dependency_files: T::Array[Dependabot::DependencyFile], root: String).returns(T.nilable(String)) }
      def self.package_manager_pin(dependency_files, root)
        manifest = dependency_files.find do |file|
          File.basename(file.name) == MANIFEST_FILENAME && File.dirname(file.path) == root
        end
        return nil unless manifest

        pinned = T.cast(JSON.parse(manifest.content.to_s), Object)
        return nil unless pinned.is_a?(Hash)

        value = pinned["packageManager"]
        value.is_a?(String) ? value : nil
      rescue JSON::ParserError
        nil
      end
      private_class_method :package_manager_pin

      # The directory pnpm treats as the workspace root, as a repository path.
      #
      # Names are relative to the job directory, which is not the workspace root
      # whenever the job targets a member: the workspace files are then fetched
      # from above and arrive as `../pnpm-workspace.yaml`, while the member's own
      # `.npmrc` keeps the bare name. Comparing names cannot tell those apart, so
      # ask `DependencyFile#path` for the repository path and compare there.
      #
      # The root is the nearest pnpm-workspace.yaml reachable without descending
      # into a project — nearest because pnpm stops at the first one it finds
      # walking up, the same rule Cargo applies to its ancestor config files.
      # With no workspace file the job directory is the only root there is.
      sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).returns(String) }
      def self.workspace_root_dir(dependency_files)
        candidates = dependency_files.select { |file| at_or_above?(file.name, WORKSPACE_FILENAME) }
        nearest = candidates.min_by { |file| file.name.scan("../").count }
        return File.dirname(nearest.path) if nearest

        first = dependency_files.first
        return "/" unless first

        Pathname.new(first.directory).cleanpath.to_path
      end
      private_class_method :workspace_root_dir

      # A name that reaches the file without descending into a project: the bare
      # name, or the same name walked up out of the job directory.
      sig { params(name: String, filename: String).returns(T::Boolean) }
      def self.at_or_above?(name, filename)
        return true if name == filename

        name.match?(%r{\A(?:\.\./)+#{Regexp.escape(filename)}\z})
      end
      private_class_method :at_or_above?

      # What the file of this name sitting at the workspace root states, or nil
      # where it states nothing. A member's own copy states nothing: pnpm takes a
      # workspace-level setting from the root during a recursive install.
      sig do
        params(
          dependency_files: T::Array[Dependabot::DependencyFile],
          root: String,
          filename: String,
          read: T.proc.params(content: String).returns(T.nilable(Symbol))
        ).returns(T.nilable(Symbol))
      end
      def self.stated_at(dependency_files, root, filename, &read)
        stated = T.let(nil, T.nilable(Symbol))
        dependency_files.each do |file|
          next unless File.basename(file.name) == filename
          next unless File.dirname(file.path) == root

          value = yield(file.content.to_s)
          stated = value unless value.nil?
        end
        stated
      end
      private_class_method :stated_at

      # Read through the parse tree rather than the loaded object, because pnpm
      # does not resolve booleans the way Ruby does. pnpm parses with js-yaml on
      # the YAML 1.2 core schema, where only `true`/`false` (any capitalisation)
      # are booleans and everything else — `'false'`, `"false"`, `no`, `off` — is
      # a string, and a string is not `false`. Psych follows YAML 1.1, which
      # resolves `no` and `off` to false as well, so loading and inspecting the
      # value would read four settings as disabling the shared lockfile that
      # pnpm leaves enabled. Measured on pnpm 10.34.5: only the bare `false`
      # produces a lockfile per project.
      #
      # A key that is present but holds one of those strings still counts as
      # stated. pnpm merges the two files by key, so such a value both leaves the
      # shared lockfile on and stops `.npmrc` being consulted — measured: with
      # `sharedWorkspaceLockfile: 'false'` beside `shared-workspace-lockfile=false`
      # pnpm writes one shared lockfile, where dropping the key writes one per
      # project.
      sig { params(content: String).returns(T.nilable(Symbol)) }
      def self.workspace_setting(content)
        # `Psych.parse` answers `false`, not nil, for a file holding no document at
        # all — empty, blank, or nothing but comments — and `&.` does not short
        # circuit on that. Ask what it is rather than assume it is a document.
        document = Psych.parse(content)
        return unless document.is_a?(Psych::Nodes::Document)

        root = document.root
        return unless root.is_a?(Psych::Nodes::Mapping)

        value = resolve_alias(value_for(root, WORKSPACE_SETTING), root)
        return unless value

        boolean = value.is_a?(Psych::Nodes::Scalar) ? core_schema_boolean(value) : nil
        return OTHER if boolean.nil?

        boolean ? ENABLED : DISABLED
      rescue Psych::Exception
        nil
      end

      # The value node for a top-level key, or nil when the key is absent. Flow
      # and block mappings are the same node.
      sig { params(mapping: Psych::Nodes::Mapping, key: String).returns(T.nilable(Psych::Nodes::Node)) }
      def self.value_for(mapping, key)
        mapping.children.each_slice(2) do |name, value|
          return value if name.is_a?(Psych::Nodes::Scalar) && name.value == key
        end
        nil
      end
      private_class_method :value_for

      # The node an alias stands for. js-yaml resolves `sharedWorkspaceLockfile:
      # *disabled` to whatever `&disabled` anchored, so reading the alias node
      # itself would see no scalar and report the key as holding something other
      # than a boolean. Psych does not resolve aliases in the parse tree, so find
      # the anchored node and answer with that.
      sig do
        params(node: T.nilable(Psych::Nodes::Node), root: Psych::Nodes::Node)
          .returns(T.nilable(Psych::Nodes::Node))
      end
      def self.resolve_alias(node, root)
        return node unless node.is_a?(Psych::Nodes::Alias)

        anchored(root, node.anchor)
      end
      private_class_method :resolve_alias

      # The first node carrying this anchor, searched depth first. YAML requires
      # an anchor to be defined before it is used, so the first match is the one
      # in scope.
      sig { params(node: Psych::Nodes::Node, name: String).returns(T.nilable(Psych::Nodes::Node)) }
      def self.anchored(node, name)
        return node if anchor_of(node) == name

        node.children&.each do |child|
          found = anchored(child, name)
          return found if found
        end
        nil
      end
      private_class_method :anchored

      # The anchor a node defines, or nil. An alias carries the anchor it refers
      # to rather than one it defines, so it never answers here.
      sig { params(node: Psych::Nodes::Node).returns(T.nilable(String)) }
      def self.anchor_of(node)
        case node
        when Psych::Nodes::Alias then nil
        when Psych::Nodes::Scalar, Psych::Nodes::Mapping, Psych::Nodes::Sequence then node.anchor
        end
      end
      private_class_method :anchor_of

      # A quoted scalar is a string whatever it spells, so only an unquoted
      # `true`/`false` counts.
      sig { params(node: Psych::Nodes::Scalar).returns(T.nilable(T::Boolean)) }
      def self.core_schema_boolean(node)
        return if node.quoted

        case node.value
        when "true", "True", "TRUE" then true
        when "false", "False", "FALSE" then false
        end
      end
      private_class_method :core_schema_boolean

      # `.npmrc` is INI, which pnpm reads with its own parser: the value is a
      # string and `false` is the only thing that turns the setting off. The last
      # assignment wins, and both `#` and `;` start a comment.
      sig { params(content: String).returns(T.nilable(Symbol)) }
      def self.npmrc_setting(content)
        key = /["']?#{Regexp.escape(NPMRC_SETTING)}["']?/o
        line = content.lines.reverse_each.find { |candidate| candidate.match?(/^\s*#{key}\s*=/) }
        return unless line

        match = line.match(/^\s*#{key}\s*=\s*["']?(\w+)["']?\s*(?:[#;].*)?$/)
        return unless match

        case T.must(match[1]).downcase
        when "true" then ENABLED
        when "false" then DISABLED
        end
      end
    end
  end
end
