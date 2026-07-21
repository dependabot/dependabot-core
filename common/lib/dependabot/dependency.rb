# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency_requirement"
require "dependabot/version"

module Dependabot
  class Dependency
    extend T::Sig

    RequirementInput = T.type_alias do
      T.any(
        Dependabot::DependencyRequirement,
        T::Hash[Dependabot::DependencyRequirement::Key, T.anything]
      )
    end
    Metadata = T.type_alias { T::Hash[Symbol, Object] }
    SubdependencyMetadata = T.type_alias { T::Hash[Symbol, Object] }

    @production_checks = T.let(
      {},
      T::Hash[String, T.proc.params(arg0: T::Array[String]).returns(T::Boolean)]
    )
    @display_name_builders = T.let({}, T::Hash[String, T.proc.params(arg0: String).returns(String)])
    @name_normalisers = T.let({}, T::Hash[String, T.proc.params(arg0: String).returns(String)])
    @humanized_previous_version_builders = T.let(
      {},
      T::Hash[String, T.proc.params(arg0: Dependency).returns(T.nilable(String))]
    )

    sig do
      params(package_manager: String).returns(T.proc.params(arg0: T::Array[String]).returns(T::Boolean))
    end
    def self.production_check_for_package_manager(package_manager)
      production_check = @production_checks[package_manager]
      return production_check if production_check

      raise "Unsupported package_manager #{package_manager}"
    end

    sig do
      params(
        package_manager: String,
        production_check: T.proc.params(arg0: T::Array[String]).returns(T::Boolean)
      )
        .returns(T.proc.params(arg0: T::Array[String]).returns(T::Boolean))
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

    sig do
      params(
        package_manager: String
      ).returns(T.nilable(T.proc.params(arg0: Dependency).returns(T.nilable(String))))
    end
    def self.humanized_previous_version_builder_for_package_manager(package_manager)
      @humanized_previous_version_builders[package_manager]
    end

    sig do
      params(
        package_manager: String,
        builder: T.proc.params(arg0: Dependency).returns(T.nilable(String))
      ).void
    end
    def self.register_humanized_previous_version_builder(package_manager, builder)
      @humanized_previous_version_builders[package_manager] = builder
    end

    sig { returns(String) }
    attr_reader :name

    sig { returns(T.nilable(String)) }
    attr_reader :version

    sig { returns(T::Array[Dependabot::DependencyRequirement]) }
    attr_reader :requirements

    sig { returns(String) }
    attr_reader :package_manager

    sig { returns(T.nilable(String)) }
    attr_reader :previous_version

    sig { returns(T.nilable(T::Array[Dependabot::DependencyRequirement])) }
    attr_reader :previous_requirements

    sig { returns(T.nilable(String)) }
    attr_accessor :directory

    sig { returns(T.nilable(T::Array[SubdependencyMetadata])) }
    attr_reader :subdependency_metadata

    sig { returns(Metadata) }
    attr_reader :metadata

    # Attribution metadata for group membership tracking
    sig { returns(T.nilable(String)) }
    attr_accessor :attribution_source_group

    sig { returns(T.nilable(Symbol)) }
    attr_accessor :attribution_selection_reason

    sig { returns(T.nilable(String)) }
    attr_accessor :attribution_directory

    sig { returns(T.nilable(Time)) }
    attr_accessor :attribution_timestamp

    # rubocop:disable Metrics/PerceivedComplexity
    sig do
      params(
        name: String,
        requirements: T::Array[RequirementInput],
        package_manager: String,
        # TODO: Make version a Dependabot::Version everywhere
        version: T.nilable(T.any(String, Dependabot::Version)),
        previous_version: T.nilable(String),
        previous_requirements: T.nilable(T::Array[RequirementInput]),
        directory: T.nilable(String),
        subdependency_metadata:
          T.nilable(T::Array[T::Hash[Dependabot::DependencyRequirement::Key, T.anything]]),
        removed: T::Boolean,
        metadata: T.nilable(T::Hash[Dependabot::DependencyRequirement::Key, T.anything])
      ).void
    end
    def initialize(
      name:,
      requirements:,
      package_manager:,
      version: nil,
      previous_version: nil,
      previous_requirements: nil,
      directory: nil,
      subdependency_metadata: [],
      removed: false,
      metadata: {}
    )
      @name = name
      @version = T.let(
        case version
        when Dependabot::Version then version.to_s
        when String then version
        end,
        T.nilable(String)
      )
      @version = nil if @version == ""
      @requirements = T.let(
        requirements.map { |req| parse_requirement(req) },
        T::Array[Dependabot::DependencyRequirement]
      )
      @previous_version = previous_version
      @previous_version = nil if @previous_version == ""
      @previous_requirements = T.let(
        previous_requirements&.map { |req| parse_requirement(req) },
        T.nilable(T::Array[Dependabot::DependencyRequirement])
      )
      @package_manager = package_manager
      @directory = directory
      unless top_level? || subdependency_metadata == []
        @subdependency_metadata = T.let(
          subdependency_metadata&.map { |h| symbolize_keys(h) },
          T.nilable(T::Array[SubdependencyMetadata])
        )
      end
      @removed = removed
      @metadata = T.let(symbolize_keys(metadata || {}), Metadata)
      check_values
    end
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

    sig { returns(T::Hash[String, Object]) }
    def to_h
      result = T.let(
        {
          "name" => name,
          "version" => version,
          "requirements" => requirements.map(&:to_h),
          "previous_version" => previous_version,
          "previous_requirements" => previous_requirements&.map(&:to_h),
          "directory" => directory,
          "package_manager" => package_manager,
          "subdependency_metadata" => subdependency_metadata,
          "removed" => removed? || nil
        },
        T::Hash[String, Object]
      )
      result.compact
    end

    sig { returns(T::Boolean) }
    def appears_in_lockfile?
      !!(previous_version || (version && previous_requirements.nil?))
    end

    sig { returns(T::Boolean) }
    def production?
      return subdependency_production_check unless top_level?

      groups = requirements.flat_map { |requirement| (requirement.groups || []).map(&:to_s) }

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
      custom_version = custom_humanized_previous_version
      return custom_version if custom_version

      default_humanized_previous_version
    end

    sig { returns(T.nilable(String)) }
    def humanized_version
      return "removed" if removed?
      return nil if version.nil?

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

    sig { params(requirements: T::Array[Dependabot::DependencyRequirement]).returns(T.nilable(String)) }
    def docker_digest_from_reqs(requirements)
      requirements
        .filter_map { |requirement| string_detail(requirement.source, "digest") }
        .first
    end

    sig { returns(T.nilable(String)) }
    def previous_ref
      return nil if previous_requirements.nil?

      previous_refs = T.must(previous_requirements).filter_map do |requirement|
        string_detail(requirement.source, "ref")
      end.uniq
      previous_refs.first if previous_refs.one?
    end

    sig { returns(T.nilable(String)) }
    def new_ref
      new_refs = requirements.filter_map do |requirement|
        string_detail(requirement.source, "ref")
      end.uniq
      new_refs.first if new_refs.one?
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

      raise TypeError, "all_versions metadata must be an array of dependencies" unless all_versions.is_a?(Array)

      all_versions.filter_map do |dependency|
        case dependency
        when Dependency then dependency.version
        when String then dependency
        else raise TypeError, "all_versions metadata must contain dependencies or version strings"
        end
      end
    end

    # This dependency is being indirectly updated by an update to another
    # dependency. We don't need to try and update it ourselves but want to
    # surface it to the user in the PR.
    sig { returns(T.nilable(T::Boolean)) }
    def informational_only?
      value = metadata[:information_only]
      case value
      when nil then nil
      when true, false then value
      else raise TypeError, "information_only metadata must be a boolean"
      end
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

    sig { returns(T::Array[Dependabot::DependencyRequirement]) }
    def specific_requirements
      requirements.select do |requirement|
        value = requirement.requirement
        value && requirement_class.new(value).specific?
      end
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
        .returns(T.nilable(Dependabot::DependencyRequirement::Details))
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

      type = details[:type] || details["type"]
      raise TypeError, "dependency source type must be a string" unless type.is_a?(String)

      type
    end

    sig { returns(T::Array[Dependabot::DependencyRequirement::Details]) }
    def all_sources
      if top_level?
        requirements.filter_map(&:source)
      elsif subdependency_metadata
        T.must(subdependency_metadata).filter_map do |data|
          details_hash(data[:source], "subdependency source")
        end
      else
        []
      end
    end

    sig { returns(T::Boolean) }
    def requirements_changed?
      (requirements - T.must(previous_requirements)).any?
    end

    private

    sig { returns(T.nilable(String)) }
    def custom_humanized_previous_version
      builder = self.class.humanized_previous_version_builder_for_package_manager(package_manager)
      return nil unless builder

      builder.call(self)
    end

    sig { returns(T.nilable(String)) }
    def default_humanized_previous_version
      # If we don't have a previous version, we *may* still be able to figure
      # one out if a ref was provided and has been changed (in which case the
      # previous ref was essentially the version).
      return (ref_changed? ? previous_ref : nil) if previous_version.nil?

      return humanized_sha_previous_version if T.must(previous_version).match?(/^[0-9a-f]{40}/)
      return humanized_docker_previous_version if version == previous_version && package_manager == "docker"

      previous_version
    end

    sig { returns(T.nilable(String)) }
    def humanized_sha_previous_version
      return previous_ref if ref_changed? && previous_ref

      "`#{T.must(previous_version)[0..6]}`"
    end

    sig { returns(String) }
    def humanized_docker_previous_version
      digest = docker_digest_from_reqs(T.must(previous_requirements))
      "`#{T.must(T.must(digest).split(':').last)[0..6]}`"
    end

    sig { void }
    def check_values
      check_subdependency_metadata
    end

    sig { void }
    def check_subdependency_metadata
      return unless subdependency_metadata

      unless subdependency_metadata.is_a?(Array) &&
             T.must(subdependency_metadata).all?(Hash)
        raise ArgumentError, "subdependency_metadata must be an array of hashes"
      end
    end

    sig do
      params(
        requirement: RequirementInput
      ).returns(Dependabot::DependencyRequirement)
    end
    def parse_requirement(requirement)
      return requirement if requirement.is_a?(Dependabot::DependencyRequirement)

      Dependabot::DependencyRequirement.from_hash(requirement)
    end

    sig do
      params(
        hash: T::Hash[Dependabot::DependencyRequirement::Key, T.anything]
      ).returns(T::Hash[Symbol, Object])
    end
    def symbolize_keys(hash)
      hash.each_with_object(T.let({}, T::Hash[Symbol, Object])) do |(raw_key, raw_value), result|
        key = T.let(raw_key, Object)
        raise TypeError, "metadata keys must be strings or symbols" unless key.is_a?(String) || key.is_a?(Symbol)

        result[key.to_sym] = T.cast(raw_value, Object)
      end
    end

    sig do
      params(
        value: T.nilable(Object),
        name: String
      ).returns(T.nilable(Dependabot::DependencyRequirement::Details))
    end
    def details_hash(value, name)
      return if value.nil?
      raise TypeError, "#{name} must be a hash" unless value.is_a?(Hash)

      value.each_with_object(T.let({}, Dependabot::DependencyRequirement::Details)) do |(raw_key, raw_value), result|
        key = T.cast(raw_key, Object)
        raise TypeError, "#{name} keys must be strings or symbols" unless key.is_a?(String) || key.is_a?(Symbol)

        result[key] = T.cast(raw_value, Object)
      end
    end

    sig do
      params(
        details: T.nilable(Dependabot::DependencyRequirement::Details),
        key: String
      ).returns(T.nilable(String))
    end
    def string_detail(details, key)
      return unless details

      value = details[key] || details[key.to_sym]
      value if value.is_a?(String)
    end
  end
end
