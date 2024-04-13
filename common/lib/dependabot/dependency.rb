# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/version"

module Dependabot
  class Dependency
    extend T::Sig

    @production_checks = T.let(
      {},
      T::Hash[String, T.proc.params(arg0: T::Array[T.untyped]).returns(T::Boolean)]
    )
    @display_name_builders = T.let({}, T::Hash[String, T.proc.params(arg0: String).returns(String)])
    @name_normalisers = T.let({}, T::Hash[String, T.proc.params(arg0: String).returns(String)])

    sig do
      params(package_manager: String).returns(T.proc.params(arg0: T::Array[T.untyped]).returns(T::Boolean))
    end
    def self.production_check_for_package_manager(package_manager)
      production_check = @production_checks[package_manager]
      return production_check if production_check

      raise "Unsupported package_manager #{package_manager}"
    end

    sig do
      params(
        package_manager: String,
        production_check: T.proc.params(arg0: T::Array[T.untyped]).returns(T::Boolean)
      )
        .returns(T.proc.params(arg0: T::Array[T.untyped]).returns(T::Boolean))
    end
    def self.register_production_check(package_manager, production_check)
      @production_checks[package_manager] = production_check
    end

    sig { params(package_manager: String).returns(T.nilable(T.proc.params(arg0: String).returns(String))) }
    def self.display_name_builder_for_package_manager(package_manager)
      @display_name_builders[package_manager]
    end

    sig { params(package_manager: String, name_builder: T.proc.params(arg0: String).returns(String)).void }
    def self.register_display_name_builder(package_manager, name_builder)
      @display_name_builders[package_manager] = name_builder
    end

    sig { params(package_manager: String).returns(T.nilable(T.proc.params(arg0: String).returns(String))) }
    def self.name_normaliser_for_package_manager(package_manager)
      @name_normalisers[package_manager] || ->(name) { name }
    end

    sig do
      params(
        package_manager: String,
        name_builder: T.proc.params(arg0: String).returns(String)
      ).void
    end
    def self.register_name_normaliser(package_manager, name_builder)
      @name_normalisers[package_manager] = name_builder
    end

    sig { returns(String) }
    attr_reader :name

    sig { returns(T.nilable(String)) }
    attr_reader :version

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    attr_reader :requirements

    sig { returns(String) }
    attr_reader :package_manager

    sig { returns(T.nilable(String)) }
    attr_reader :previous_version

    sig { returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) }
    attr_reader :previous_requirements

    sig { returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) }
    attr_reader :subdependency_metadata

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_reader :metadata

    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/PerceivedComplexity
    sig do
      params(
        name: String,
        requirements: T::Array[T::Hash[T.any(Symbol, String), T.untyped]],
        package_manager: String,
        # TODO: Make version a Dependabot::Version everywhere
        version: T.nilable(T.any(String, Dependabot::Version)),
        previous_version: T.nilable(String),
        previous_requirements: T.nilable(T::Array[T::Hash[T.any(Symbol, String), T.untyped]]),
        subdependency_metadata: T.nilable(T::Array[T::Hash[T.any(Symbol, String), String]]),
        removed: T::Boolean,
        metadata: T.nilable(T::Hash[T.any(Symbol, String), String])
      ).void
    end
    def initialize(name:, requirements:, package_manager:, version: nil,
                   previous_version: nil, previous_requirements: nil,
                   subdependency_metadata: [], removed: false, metadata: {})
      @name = name
      @version = T.let(
        case version
        when Dependabot::Version then version.to_s
        when String then version
        end,
        T.nilable(String)
      )
      @version = nil if @version == ""
      @requirements = T.let(requirements.map { |req| symbolize_keys(req) }, T::Array[T::Hash[Symbol, T.untyped]])
      @previous_version = previous_version
      @previous_version = nil if @previous_version == ""
      @previous_requirements = T.let(
        previous_requirements&.map { |req| symbolize_keys(req) },
        T.nilable(T::Array[T::Hash[Symbol, T.untyped]])
      )
      @package_manager = package_manager
      unless top_level? || subdependency_metadata == []
        @subdependency_metadata = T.let(
          subdependency_metadata&.map { |h| symbolize_keys(h) },
          T.nilable(T::Array[T::Hash[Symbol, T.untyped]])
        )
      end
      @removed = removed
      @metadata = T.let(symbolize_keys(metadata || {}), T::Hash[Symbol, T.untyped])

      check_values
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/PerceivedComplexity

    sig { returns(T::Boolean) }
    def top_level?
      requirements.any?
    end

    sig { returns(T::Boolean) }
    def removed?
      @removed
    end

    sig { returns(T.nilable(Dependabot::Version)) }
    def numeric_version
      return unless version && version_class.correct?(version)

      @numeric_version ||= T.let(version_class.new(T.must(version)), T.nilable(Dependabot::Version))
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def to_h
      {
        "name" => name,
        "version" => version,
        "requirements" => requirements,
        "previous_version" => previous_version,
        "previous_requirements" => previous_requirements,
        "package_manager" => package_manager,
        "subdependency_metadata" => subdependency_metadata,
        "removed" => removed? ? true : nil
      }.compact
    end

    sig { returns(T::Boolean) }
    def appears_in_lockfile?
      !!(previous_version || (version && previous_requirements.nil?))
    end

    sig { returns(T::Boolean) }
    def production?
      return subdependency_production_check unless top_level?

      groups = requirements.flat_map { |r| r.fetch(:groups).map(&:to_s) }

      self.class
          .production_check_for_package_manager(package_manager)
          .call(groups)
    end

    sig { returns(T::Boolean) }
    def subdependency_production_check
      !subdependency_metadata&.all? { |h| h[:production] == false }
    end

    sig { returns(String) }
    def display_name
      display_name_builder =
        self.class.display_name_builder_for_package_manager(package_manager)
      return name unless display_name_builder

      display_name_builder.call(name)
    end

    sig { returns(T.nilable(String)) }
    def humanized_previous_version
      # If we don't have a previous version, we *may* still be able to figure
      # one out if a ref was provided and has been changed (in which case the
      # previous ref was essentially the version).
      if previous_version.nil?
        return ref_changed? ? previous_ref : nil
      end

      if T.must(previous_version).match?(/^[0-9a-f]{40}/)
        return previous_ref if ref_changed? && previous_ref

        "`#{T.must(previous_version)[0..6]}`"
      elsif version == previous_version &&
            package_manager == "docker"
        digest = docker_digest_from_reqs(T.must(previous_requirements))
        "`#{T.must(T.must(digest).split(':').last)[0..6]}`"
      else
        previous_version
      end
    end

    sig { returns(T.nilable(String)) }
    def humanized_version
      return "removed" if removed?

      if T.must(version).match?(/^[0-9a-f]{40}/)
        return new_ref if ref_changed? && new_ref

        "`#{T.must(version)[0..6]}`"
      elsif version == previous_version &&
            package_manager == "docker"
        digest = docker_digest_from_reqs(requirements)
        "`#{T.must(T.must(digest).split(':').last)[0..6]}`"
      else
        version
      end
    end

    sig { params(requirements: T::Array[T::Hash[Symbol, T.untyped]]).returns(T.nilable(String)) }
    def docker_digest_from_reqs(requirements)
      requirements
        .filter_map { |r| r.dig(:source, "digest") || r.dig(:source, :digest) }
        .first
    end

    sig { returns(T.nilable(String)) }
    def previous_ref
      return nil if previous_requirements.nil?

      previous_refs = T.must(previous_requirements).filter_map do |r|
        r.dig(:source, "ref") || r.dig(:source, :ref)
      end.uniq
      previous_refs.first if previous_refs.count == 1
    end

    sig { returns(T.nilable(String)) }
    def new_ref
      new_refs = requirements.filter_map do |r|
        r.dig(:source, "ref") || r.dig(:source, :ref)
      end.uniq
      new_refs.first if new_refs.count == 1
    end

    sig { returns(T::Boolean) }
    def ref_changed?
      previous_ref != new_ref
    end

    # Returns all detected versions of the dependency. Only ecosystems that
    # support this feature will return more than the current version.
    sig { returns(T::Array[T.nilable(String)]) }
    def all_versions
      all_versions = metadata[:all_versions]
      return [version].compact unless all_versions

      all_versions.filter_map(&:version)
    end

    # This dependency is being indirectly updated by an update to another
    # dependency. We don't need to try and update it ourselves but want to
    # surface it to the user in the PR.
    sig { returns(T.nilable(T::Boolean)) }
    def informational_only?
      metadata[:information_only]
    end

    sig { params(other: T.anything).returns(T::Boolean) }
    def ==(other)
      case other
      when Dependency
        to_h == other.to_h
      else
        false
      end
    end

    sig { returns(Integer) }
    def hash
      to_h.hash
    end

    sig { params(other: T.anything).returns(T::Boolean) }
    def eql?(other)
      self == other
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def specific_requirements
      requirements.select { |r| requirement_class.new(r[:requirement]).specific? }
    end

    sig { returns(T.class_of(Dependabot::Requirement)) }
    def requirement_class
      Utils.requirement_class_for_package_manager(package_manager)
    end

    sig { returns(T.class_of(Dependabot::Version)) }
    def version_class
      Utils.version_class_for_package_manager(package_manager)
    end

    sig do
      params(
        allowed_types: T.nilable(T::Array[String])
      )
        .returns(T.nilable(T::Hash[T.any(String, Symbol), T.untyped]))
    end
    def source_details(allowed_types: nil)
      sources = all_sources.uniq.compact
      sources.select! { |source| allowed_types.include?(source[:type].to_s) } if allowed_types

      git = allowed_types == ["git"]

      if (git && sources.map { |s| s[:url] }.uniq.count > 1) || (!git && sources.count > 1)
        raise "Multiple sources! #{sources.join(', ')}"
      end

      sources.first
    end

    sig { returns(T.nilable(String)) }
    def source_type
      details = source_details
      return "default" if details.nil?

      details[:type] || details.fetch("type")
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def all_sources
      if top_level?
        requirements.map { |requirement| requirement.fetch(:source) }
      elsif subdependency_metadata
        T.must(subdependency_metadata).filter_map { |data| data[:source] }
      else
        []
      end
    end

    private

    sig { void }
    def check_values
      check_requirement_fields
      check_subdependency_metadata
    end

    sig { void }
    def check_requirement_fields
      requirement_fields = [requirements, previous_requirements].compact
      unless requirement_fields.all?(Array) &&
             requirement_fields.flatten.all?(Hash)
        raise ArgumentError, "requirements must be an array of hashes"
      end

      required_keys = %i(requirement file groups source)
      optional_keys = %i(metadata)
      unless requirement_fields.flatten
                               .all? { |r| required_keys.sort == (r.keys - optional_keys).sort }
        raise ArgumentError, "each requirement must have the following " \
                             "required keys: #{required_keys.join(', ')}." \
                             "Optionally, it may have the following keys: " \
                             "#{optional_keys.join(', ')}."
      end

      return if requirement_fields.flatten.none? { |r| r[:requirement] == "" }

      raise ArgumentError, "blank strings must not be provided as requirements"
    end

    sig { void }
    def check_subdependency_metadata
      return unless subdependency_metadata

      unless subdependency_metadata.is_a?(Array) &&
             T.must(subdependency_metadata).all?(Hash)
        raise ArgumentError, "subdependency_metadata must be an array of hashes"
      end
    end

    sig { params(hash: T::Hash[T.any(Symbol, String), T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def symbolize_keys(hash)
      hash.keys.to_h { |k| [k.to_sym, hash[k]] }
    end
  end
end
