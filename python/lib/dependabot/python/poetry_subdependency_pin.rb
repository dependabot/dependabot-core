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
    # TODO: decline when a package is locked at several versions; one pin can't satisfy them all.
    # TODO: scope pins for packages that are only in non-main groups (group-keyed lock markers).
    # TODO: pin into the right PEP 735 `[dependency-groups]` entry; only declarations are updated today.
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
        const :markers, T::Array[String]
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

        pin!(project_object, "#{@name}#{requirement}")
      end

      # Adds a pin that keeps the package's locked scope. Raises ScopeNotReproducible for an optional
      # package with no extras in its markers.
      # rubocop:disable-next Sorbet/ForbidTUntyped
      sig { params(project_object: T::Hash[String, T.untyped], pin: String).void }
      def pin!(project_object, pin)
        main_pin, extra_pins = pins_for(pin)

        (project_object["dependencies"] ||= []) << main_pin if main_pin
        extra_pins.each do |extra, extra_pin|
          extras = project_object["optional-dependencies"] ||= {}
          (extras[declared_extra_name(extras, extra)] ||= []) << extra_pin
        end
      end

      private

      # Returns [main_pin, extra_pins]. Raises ScopeNotReproducible for an optional package with no
      # extras in its markers (legacy lockfile format): pinning it unconditionally would promote it
      # into the main install.
      sig { params(pin: String).returns([T.nilable(String), T::Hash[String, String]]) }
      def pins_for(pin)
        return [main_pin(pin), {}] if entries.empty? || entries.any? { |entry| !entry.optional }

        [nil, extra_pins(pin)]
      end

      # An entry with no markers applies everywhere, so the combined scope is then unconditional.
      sig { params(pin: String).returns(String) }
      def main_pin(pin)
        return pin if entries.empty? || entries.any? { |entry| entry.markers.empty? }

        "#{pin}; #{entries.flat_map(&:markers).uniq.join(' or ')}"
      end

      # Lock markers hold the normalised extra name, which may differ from how the project spells it.
      sig { params(extras: T::Hash[String, T::Array[DeclarationEntry]], name: String).returns(String) }
      def declared_extra_name(extras, name)
        extras.keys.find { |key| normalise_extra(key) == normalise_extra(name) } || name
      end

      sig { params(name: String).returns(String) }
      def normalise_extra(name)
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
          marker = entry[prefix.length..]&.match(/(\s*;.*)/)&.to_a&.fetch(1, "")
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

          markers = entry["markers"]
          markers = markers.values if markers.is_a?(Hash)
          LockedEntry.new(
            optional: entry["optional"] == true,
            markers: Array(markers).map { |marker| "(#{marker})" }
          )
        end
      end

      sig { params(pin: String).returns(T::Hash[String, String]) }
      def extra_pins(pin)
        markers = entries.flat_map(&:markers).uniq
        extras = markers.flat_map { |marker| marker.scan(EXTRA_NAME).flatten }.uniq
        raise ScopeNotReproducible, "#{@name} is optional but has no recorded extras" if extras.empty?

        extras.to_h do |extra|
          scoped = markers.select { |marker| marker.scan(EXTRA_NAME).flatten.include?(extra) }
          [extra, "#{pin}; #{scoped.join(' or ')}"]
        end
      end
    end
  end
end
