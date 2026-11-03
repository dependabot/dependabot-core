# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
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

      class << self
        extend T::Sig

        # Returns [main_pin, extra_pins]. A non-optional package gets one main pin; Poetry accepts
        # `extra == "..."` inside project.dependencies, so its extra branches are preserved there.
        # An optional package is pinned in each extra its markers name. An optional package with no
        # markers (legacy lockfile format, where extras live on another package's entry) is left
        # unpinned rather than promoted into the unconditional install, so it may drift.
        sig do
          params(lockfile: T.nilable(Dependabot::DependencyFile), name: String, pin: String)
            .returns([T.nilable(String), T::Hash[String, String]])
        end
        def pins_for_dependency(lockfile, name, pin)
          package = packages_from_lockfile(lockfile).find { |pkg| NameNormaliser.normalise(pkg.name) == name }
          return [pin, {}] unless package

          markers = package.marker_strings
          return [pin_with_marker(pin, markers.first), {}] unless package.optional

          extra_pins = T.let({}, T::Hash[String, String])
          markers.each do |marker|
            marker.scan(EXTRA_NAME).flatten.each { |extra| extra_pins[extra] ||= pin_with_marker(pin, marker) }
          end

          [nil, extra_pins]
        end

        private

        sig do
          params(lockfile: T.nilable(Dependabot::DependencyFile))
            .returns(T::Array[Dependabot::Python::FileParser::PoetryLock::Package])
        end
        def packages_from_lockfile(lockfile)
          return [] unless lockfile

          Dependabot::Python::FileParser::PoetryLock.from_file(lockfile).packages
        end

        sig { params(pin: String, marker: T.nilable(String)).returns(String) }
        def pin_with_marker(pin, marker)
          marker ? "#{pin}; #{marker}" : pin
        end
      end
    end
  end
end
