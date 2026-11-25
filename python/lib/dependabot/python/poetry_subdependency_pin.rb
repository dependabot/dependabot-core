# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency_file"
require "dependabot/python/file_parser/poetry_lock"
require "dependabot/python/file_parser/pyproject_document"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    # Pins a sub-dependency of a PEP 621-only project in a scratch manifest. The pin keeps
    # the package's locked markers, so Poetry records the same install conditions; an unconditional pin
    # would promote an extra-only or platform-specific package into every install.
    #
    # A package locked at several versions (one per Python branch) is declined: a single pin can't
    # satisfy every branch.
    class PoetrySubdependencyPin
      extend T::Sig

      EXTRA_NAME = /extra\s*==\s*"([^"]+)"/
      private_constant :EXTRA_NAME

      # Raised when a pin can't reproduce the package's install conditions, so the update is declined
      # rather than risk locking a version outside its intended scope.
      class ScopeNotReproducible < StandardError; end

      sig { params(lockfile: T.nilable(Dependabot::DependencyFile), name: String).void }
      def initialize(lockfile, name)
        @lockfile = lockfile
        @name = name
      end

      # Updates every declaration of the dependency in place; a sub-dependency isn't declared anywhere,
      # so it is pinned instead to force Poetry's solver to consider the target version.
      sig { params(document: FileParser::PyprojectDocument, requirement: String).void }
      def set_requirement!(document, requirement)
        return unless document.project?

        ensure_single_version!
        return if document.replace_pep621_requirement(name: @name, requirement: requirement).positive?

        pin!(document, "#{@name}#{requirement}")
      end

      # A package locked at several versions has per-marker scopes that one target version can't reproduce.
      sig { void }
      def ensure_single_version!
        raise ScopeNotReproducible, "#{@name} is locked at several versions" if entries.size > 1
      end

      # Adds a pin per place the package is locked (main, extras, other groups), each keeping its locked
      # markers. Raises ScopeNotReproducible for a package locked at several versions, or an optional
      # package with no extras in its markers.
      sig { params(document: FileParser::PyprojectDocument, pin: String).void }
      def pin!(document, pin)
        return unless document.project?

        main_pin, extra_pins, group_pins = pins_for(pin)
        document.append_pep621_pins(main: main_pin, extras: extra_pins, groups: group_pins)
      end

      private

      # Returns [main_pin, extra_pins, group_pins]. Raises ScopeNotReproducible for a package locked at
      # several versions, or an optional package with no extras in its markers (legacy lockfile format):
      # pinning it unconditionally would promote it into the main install.
      sig { params(pin: String).returns([T.nilable(String), T::Hash[String, String], T::Hash[String, String]]) }
      def pins_for(pin)
        ensure_single_version!

        entry = entries.first
        return [pin, {}, {}] unless entry

        group_pins = (entry.groups - ["main"]).to_h { |group| [group, scoped_pin(pin, entry, group)] }
        return [nil, {}, group_pins] unless entry.groups.include?("main")
        return [scoped_pin(pin, entry, "main"), {}, group_pins] unless entry.optional

        [nil, extra_pins(pin, entry), group_pins]
      end

      sig { params(pin: String, entry: FileParser::PoetryLock::Scope, group: String).returns(String) }
      def scoped_pin(pin, entry, group)
        marker = entry.markers_for(group).first
        marker ? "#{pin}; #{marker}" : pin
      end

      sig { returns(T::Array[FileParser::PoetryLock::Scope]) }
      def entries
        @entries ||= T.let(locked_entries, T.nilable(T::Array[FileParser::PoetryLock::Scope]))
      end

      sig { returns(T::Array[FileParser::PoetryLock::Scope]) }
      def locked_entries
        return [] unless @lockfile

        FileParser::PoetryLock.from_content(T.must(@lockfile.content))
                              .records_for(@name) { |name| NameNormaliser.normalise(name) }
                              .map(&:scope)
      end

      sig { params(pin: String, entry: FileParser::PoetryLock::Scope).returns(T::Hash[String, String]) }
      def extra_pins(pin, entry)
        marker = entry.markers_for("main").first.to_s
        extras = marker.scan(EXTRA_NAME).flatten.uniq
        raise ScopeNotReproducible, "#{@name} is optional but has no recorded extras" if extras.empty?

        extras.to_h { |extra| [extra, "#{pin}; #{marker}"] }
      end
    end
  end
end
