# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/errors"
require "dependabot/python/file_parser/poetry_lock"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    # Pure sub-dependencies of a PEP 621-only project (no [tool.poetry] table) need a pin added
    # directly to project.dependencies/project.optional-dependencies, both when the file updater
    # pins the final lockfile and when the version resolver pins a scratch manifest. The pin keeps
    # the package's original marker verbatim so Poetry records the same install conditions in the
    # lockfile; rewriting the marker (or pinning unconditionally) changes or drops them.
    module PoetryPep621SubdependencyScope
      extend T::Sig

      EXTRA_NAME = /extra\s*==\s*"([^"]+)"/
      private_constant :EXTRA_NAME

      # Raised when a pin can't reproduce the package's original install conditions, so the update
      # is declined rather than risk locking a version outside its intended scope.
      class ScopeNotReproducible < Dependabot::DependencyFileNotResolvable; end

      class << self
        extend T::Sig

        # Returns [main_pin, extra_pins]. A non-optional package gets one main pin; Poetry accepts
        # `extra == "..."` inside project.dependencies, so its extra branches are preserved there.
        # An optional package is pinned in each extra its markers name. A package Poetry locked as
        # several entries (one version per marker group) is pinned against the union of every
        # entry's markers, so no slice is left free to resolve to a different version.
        #
        # Raises ScopeNotReproducible for an optional package with no markers (legacy lockfile
        # format, where extras live on another package's entry): pinning it unconditionally would
        # promote it into the main install, and leaving it unpinned would let Poetry pick any
        # version.
        sig do
          params(lockfile: T.nilable(Dependabot::DependencyFile), name: String, pin: String)
            .returns([T.nilable(String), T::Hash[String, String]])
        end
        def pins_for_dependency(lockfile, name, pin)
          packages = packages_from_lockfile(lockfile).select { |pkg| NameNormaliser.normalise(pkg.name) == name }
          return [pin, {}] if packages.empty?

          return [main_pin(packages, pin), {}] unless packages.all?(&:optional)

          markers = packages.flat_map(&:marker_strings).uniq
          raise ScopeNotReproducible, "#{name} is optional but has no recorded markers" if markers.empty?

          [nil, extra_pins(markers, pin)]
        end

        private

        # An entry with no markers applies everywhere, so the combined scope is then unconditional.
        sig { params(packages: T::Array[FileParser::PoetryLock::Package], pin: String).returns(String) }
        def main_pin(packages, pin)
          return pin if packages.any? { |pkg| pkg.marker_strings.empty? }

          pin_with_marker(pin, union(packages.flat_map(&:marker_strings).uniq))
        end

        sig { params(markers: T::Array[String], pin: String).returns(T::Hash[String, String]) }
        def extra_pins(markers, pin)
          extras_by_marker = markers.to_h { |marker| [marker, marker.scan(EXTRA_NAME).flatten] }

          extras_by_marker.values.flatten.uniq.to_h do |extra|
            matching = markers.select { |marker| extras_by_marker.fetch(marker).include?(extra) }
            [extra, pin_with_marker(pin, union(matching))]
          end
        end

        sig do
          params(lockfile: T.nilable(Dependabot::DependencyFile))
            .returns(T::Array[Dependabot::Python::FileParser::PoetryLock::Package])
        end
        def packages_from_lockfile(lockfile)
          return [] unless lockfile

          Dependabot::Python::FileParser::PoetryLock.from_file(lockfile).packages
        end

        sig { params(markers: T::Array[String]).returns(T.nilable(String)) }
        def union(markers)
          return markers.first if markers.length <= 1

          markers.map { |marker| "(#{marker})" }.join(" or ")
        end

        sig { params(pin: String, marker: T.nilable(String)).returns(String) }
        def pin_with_marker(pin, marker)
          marker ? "#{pin}; #{marker}" : pin
        end
      end
    end
  end
end
