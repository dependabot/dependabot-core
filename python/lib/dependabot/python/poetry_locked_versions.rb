# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/python/name_normaliser"
require "dependabot/python/poetry_project"
require "dependabot/python/poetry_relocker"
require "dependabot/python/requirement"
require "dependabot/python/version"

module Dependabot
  module Python
    # A package that poetry.lock locks at several versions, one per marker
    # (for example `requests` 2.32.x for Python 3.9 and 2.34.x for 3.10+).
    #
    # Ruby picks a target for each locked version; the native relock helper
    # applies them as marker-scoped pins. Without pins, `poetry update <name>`
    # collapses the copies to the newest release every Python supports, which
    # downgrades the newer copy.
    #
    # Only used when the `enable_native_poetry_helper` experiment is on.
    class PoetryLockedVersions
      extend T::Sig

      # Dependency metadata key the update checker uses to hand the targets
      # to the file updater.
      METADATA_KEY = :poetry_locked_versions

      class Target < T::ImmutableStruct
        extend T::Sig

        const :previous_version, String
        const :version, String
        # Group => marker, as Poetry reports them for the locked version.
        const :markers, T::Hash[String, T.nilable(String)]

        sig { params(name: String).returns(PoetryRelocker::Pin) }
        def to_pin(name)
          PoetryRelocker::Pin.new(name: name, version: version, markers: markers)
        end

        sig { returns(T::Hash[String, Object]) }
        def to_metadata
          { "previous_version" => previous_version, "version" => version, "markers" => markers }
        end

        sig { params(value: Object).returns(Target) }
        def self.from_metadata(value)
          hash = PoetryProject::Values.object_hash(value, "locked version target")
          markers = PoetryProject::Values.object_hash(hash["markers"], "locked version target markers")
          new(
            previous_version: PoetryProject::Values.string(hash["previous_version"], "locked version target"),
            version: PoetryProject::Values.string(hash["version"], "locked version target"),
            markers: markers.transform_values { |m| PoetryProject::Values.optional_string(m, "marker") }
          )
        end
      end

      # Returns nil when the package is locked once, or locked several times
      # in a way pins can't reproduce: lockfiles older than 2.1 have no
      # per-group markers, an optional package's markers are extras, and
      # direct-source packages aren't resolved from an index.
      sig { params(project: T.nilable(PoetryProject), name: String).returns(T.nilable(PoetryLockedVersions)) }
      def self.for(project, name)
        return unless project

        locked = project.locked_versions_of(name)
        return if locked.size < 2
        return unless project.groups_and_markers_locked?
        return if locked.any? { |package| package.optional || package.direct_source? || package.markers.nil? }

        new(name, locked)
      end

      # Pins every other package locked at several versions to what's locked.
      # Without them, re-locking anything collapses those copies unless
      # pyproject.toml itself forces the split (multiple-constraint
      # declarations).
      sig do
        params(project: T.nilable(PoetryProject), except: T::Array[String]).returns(T::Array[PoetryRelocker::Pin])
      end
      def self.hold_pins(project, except:)
        return [] unless project

        skipped = except.map { |name| NameNormaliser.normalise(name) }
        project.names_locked_more_than_once.flat_map do |name|
          next [] if skipped.include?(NameNormaliser.normalise(name))

          self.for(project, name)&.hold_pins || []
        end
      end

      # True when the re-locked versions of each pinned package are exactly
      # the pinned versions, so callers don't report an update Poetry didn't
      # make.
      sig do
        params(pins: T::Array[PoetryRelocker::Pin], locked: T::Hash[String, T::Array[String]]).returns(T::Boolean)
      end
      def self.pins_applied?(pins, locked)
        pins.group_by { |pin| NameNormaliser.normalise(pin.name) }.all? do |name, by_name|
          sorted(by_name.map(&:version)) == sorted(locked.fetch(name, []))
        end
      end

      sig { params(versions: T::Array[String]).returns(T::Array[Version]) }
      def self.sorted(versions)
        versions.map { |version| Version.new(version) }.sort
      end
      private_class_method :sorted

      # The highest target that moves, or nil when none do.
      sig { params(targets: T::Array[Target]).returns(T.nilable(String)) }
      def self.highest_moved(targets)
        targets.reject { |target| target.version == target.previous_version }
               .map { |target| Version.new(target.version) }.max&.to_s
      end

      # The targets the update checker stored on an updated dependency.
      sig { params(dependency: Dependabot::Dependency).returns(T::Array[Target]) }
      def self.targets_from(dependency)
        value = dependency.metadata[METADATA_KEY]
        return [] if value.nil?

        PoetryProject::Values.array(value, "locked version targets").map { |entry| Target.from_metadata(entry) }
      end

      sig { params(name: String, locked: T::Array[PoetryProject::LockedPackage]).void }
      def initialize(name, locked)
        @name = name
        @locked = locked
      end

      sig { returns(String) }
      attr_reader :name

      # Picks the newest release for each locked version that:
      # - `releases_for` returns for that version's lowest Python (callers
      #   pass the latest version finder, so ignore rules and cooldown apply),
      # - satisfies every requirement string, and
      # - isn't older than what's locked.
      # A locked version with no such release keeps its version.
      sig do
        params(
          requirements: T::Array[String],
          releases_for: T.proc.params(min_python: T.nilable(String)).returns(T::Array[Gem::Version])
        ).returns(T::Array[Target])
      end
      def targets(requirements:, &releases_for)
        @locked.map do |package|
          current = Version.new(package.version)
          candidates = yield(package.min_python).select do |version|
            version >= current && requirements.all? { |req| satisfied?(req, version) }
          end
          Target.new(
            previous_version: package.version,
            version: candidates.max&.to_s || package.version,
            markers: T.must(package.markers)
          )
        end
      end

      sig { returns(T::Array[PoetryRelocker::Pin]) }
      def hold_pins
        @locked.map do |package|
          PoetryRelocker::Pin.new(name: name, version: package.version, markers: T.must(package.markers))
        end
      end

      private

      sig { params(requirement: String, version: Gem::Version).returns(T::Boolean) }
      def satisfied?(requirement, version)
        Requirement.requirements_array(requirement).any? { |req| req.satisfied_by?(version) }
      end
    end
  end
end
