# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"
require "dependabot/dependency_file"
require "dependabot/python/name_normaliser"
require "dependabot/python/file_updater/pyproject_preparer"

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

      # A string, or a table such as PEP 735's `{ include-group = "..." }`.
      DeclarationEntry = T.type_alias { T.any(String, T::Hash[String, String]) }
      private_constant :DeclarationEntry

      class LockedEntry < T::Struct
        const :optional, T::Boolean
        const :groups, T::Array[String]
        const :markers, T::Hash[String, T::Array[String]]

        extend T::Sig

        sig { params(group: String).returns(T::Array[String]) }
        def markers_for(group)
          markers.fetch(group, [])
        end
      end
      private_constant :LockedEntry

      sig { params(lockfile: T.nilable(Dependabot::DependencyFile), name: String).void }
      def initialize(lockfile, name)
        @lockfile = lockfile
        @name = name
      end

      # Updates every declaration of the dependency in place; a sub-dependency isn't declared anywhere,
      # so it is pinned instead to force Poetry's solver to consider the target version.
      # rubocop:disable-next Sorbet/ForbidTUntyped
      sig { params(pyproject_object: T::Hash[String, T.untyped], requirement: String).void }
      def set_requirement!(pyproject_object, requirement)
        project_object = pyproject_object["project"]
        return unless project_object
        return if declaration_arrays(pyproject_object).map { |arr| update_declarations!(arr, requirement) }.any?

        pin!(pyproject_object, "#{@name}#{requirement}")
      end

      # Adds a pin per place the package is locked (main, extras, other groups), each keeping its locked
      # markers. Raises ScopeNotReproducible for a package locked at several versions, or an optional
      # package with no extras in its markers.
      # rubocop:disable-next Sorbet/ForbidTUntyped
      sig { params(pyproject_object: T::Hash[String, T.untyped], pin: String).void }
      def pin!(pyproject_object, pin)
        project_object = pyproject_object["project"]
        return unless project_object

        main_pin, extra_pins, group_pins = pins_for(pin)

        (project_object["dependencies"] ||= []) << main_pin if main_pin
        append_pins!(project_object["optional-dependencies"] ||= {}, extra_pins)
        append_pins!(pyproject_object["dependency-groups"] ||= {}, group_pins) if group_pins.any?
      end

      private

      sig { params(table: T::Hash[String, T::Array[DeclarationEntry]], pins: T::Hash[String, String]).void }
      def append_pins!(table, pins)
        pins.each { |key, pin| (table[declared_key(table, key)] ||= []) << pin }
      end

      # Returns [main_pin, extra_pins, group_pins]. Raises ScopeNotReproducible for a package locked at
      # several versions, or an optional package with no extras in its markers (legacy lockfile format):
      # pinning it unconditionally would promote it into the main install.
      sig { params(pin: String).returns([T.nilable(String), T::Hash[String, String], T::Hash[String, String]]) }
      def pins_for(pin)
        raise ScopeNotReproducible, "#{@name} is locked at several versions" if entries.size > 1

        entry = entries.first
        return [pin, {}, {}] unless entry

        group_pins = (entry.groups - ["main"]).to_h { |group| [group, scoped_pin(pin, entry, group)] }
        return [nil, {}, group_pins] unless entry.groups.include?("main")
        return [scoped_pin(pin, entry, "main"), {}, group_pins] unless entry.optional

        [nil, extra_pins(pin, entry), group_pins]
      end

      sig { params(pin: String, entry: LockedEntry, group: String).returns(String) }
      def scoped_pin(pin, entry, group)
        marker = entry.markers_for(group).first
        marker ? "#{pin}; #{marker}" : pin
      end

      # The lock holds normalised extra and group names, which may differ from how the project spells them.
      sig { params(table: T::Hash[String, T::Array[DeclarationEntry]], name: String).returns(String) }
      def declared_key(table, name)
        table.keys.find { |key| normalise_key(key) == normalise_key(name) } || name
      end

      sig { params(name: String).returns(String) }
      def normalise_key(name)
        name.downcase.gsub(/[-_.]+/, "-")
      end

      # rubocop:disable-next Sorbet/ForbidTUntyped
      sig { params(pyproject_object: T::Hash[String, T.untyped]).returns(T::Array[T::Array[DeclarationEntry]]) }
      def declaration_arrays(pyproject_object)
        project = pyproject_object.fetch("project", {})
        tables = [project["optional-dependencies"], pyproject_object["dependency-groups"]].compact
        [project["dependencies"], *tables.flat_map(&:values)].grep(Array)
      end

      sig { params(declarations: T::Array[DeclarationEntry], requirement: String).returns(T::Boolean) }
      def update_declarations!(declarations, requirement)
        updated = T.let(false, T::Boolean)

        declarations.each_with_index do |entry, index|
          next unless entry.is_a?(String)

          match = entry.match(Python::FileUpdater::PyprojectPreparer::PEP508_PREFIX)
          next unless match && NameNormaliser.normalise(T.must(match[:name])) == @name

          prefix = T.must(match[:prefix])
          head, separator, tail = entry[prefix.length..].to_s.partition(";")
          marker = separator.empty? ? "" : "#{head[head.rstrip.length..]};#{tail}"
          declarations[index] = "#{prefix}#{requirement}#{marker}"
          updated = true
        end

        updated
      end

      sig { returns(T::Array[LockedEntry]) }
      def entries
        @entries ||= T.let(locked_entries, T.nilable(T::Array[LockedEntry]))
      end

      sig { returns(T::Array[LockedEntry]) }
      def locked_entries
        return [] unless @lockfile

        TomlRB.parse(T.must(@lockfile.content)).fetch("package", []).filter_map do |entry|
          next unless entry["name"] && NameNormaliser.normalise(entry["name"]) == @name

          # Legacy lockfiles record no groups; those entries are treated as main.
          groups = Array(entry["groups"])
          groups = ["main"] if groups.empty?
          LockedEntry.new(optional: entry["optional"] == true, groups: groups, markers: locked_markers(entry, groups))
        end
      end

      # Markers are a single string, or a table keyed by group.
      # rubocop:disable-next Sorbet/ForbidTUntyped
      sig do
        params(entry: T::Hash[String, T.untyped], groups: T::Array[String]).returns(T::Hash[String, T::Array[String]])
      end
      def locked_markers(entry, groups)
        markers = entry["markers"]
        return markers.transform_values { |marker| ["(#{marker})"] } if markers.is_a?(Hash)

        groups.to_h { |group| [group, markers ? ["(#{markers})"] : []] }
      end

      sig { params(pin: String, entry: LockedEntry).returns(T::Hash[String, String]) }
      def extra_pins(pin, entry)
        marker = entry.markers_for("main").first.to_s
        extras = marker.scan(EXTRA_NAME).flatten.uniq
        raise ScopeNotReproducible, "#{@name} is optional but has no recorded extras" if extras.empty?

        extras.to_h { |extra| [extra, "#{pin}; #{marker}"] }
      end
    end
  end
end
