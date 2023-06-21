# frozen_string_literal: true

require "dependabot/version"

module Dependabot
  class Dependency
    @production_checks = {}
    @display_name_builders = {}
    @name_normalisers = {}

    def self.production_check_for_package_manager(package_manager)
      production_check = @production_checks[package_manager]
      return production_check if production_check

      raise "Unsupported package_manager #{package_manager}"
    end

    def self.register_production_check(package_manager, production_check)
      @production_checks[package_manager] = production_check
    end

    def self.display_name_builder_for_package_manager(package_manager)
      @display_name_builders[package_manager]
    end

    def self.register_display_name_builder(package_manager, name_builder)
      @display_name_builders[package_manager] = name_builder
    end

    def self.name_normaliser_for_package_manager(package_manager)
      @name_normalisers[package_manager] || ->(name) { name }
    end

    def self.register_name_normaliser(package_manager, name_builder)
      @name_normalisers[package_manager] = name_builder
    end

    attr_reader :name, :version, :requirements, :package_manager,
                :previous_version, :previous_requirements,
                :subdependency_metadata, :metadata

    def initialize(name:, requirements:, package_manager:, version: nil,
                   previous_version: nil, previous_requirements: nil,
                   subdependency_metadata: [], removed: false, metadata: {})
      @name = name
      @version = version
      @requirements = requirements.map { |req| symbolize_keys(req) }
      @previous_version = previous_version
      @previous_requirements =
        previous_requirements&.map { |req| symbolize_keys(req) }
      @package_manager = package_manager
      unless top_level? || subdependency_metadata == []
        @subdependency_metadata = subdependency_metadata&.
                                  map { |h| symbolize_keys(h) }
      end
      @removed = removed
      @metadata = symbolize_keys(metadata || {})

      check_values
    end

    def top_level?
      requirements.any?
    end

    def removed?
      @removed
    end

    def numeric_version
      @numeric_version ||= version_class.new(version) if version && version_class.correct?(version)
    end

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

    def appears_in_lockfile?
      previous_version || (version && previous_requirements.nil?)
    end

    def production?
      return subdependency_production_check unless top_level?

      groups = requirements.flat_map { |r| r.fetch(:groups).map(&:to_s) }

      self.class.
        production_check_for_package_manager(package_manager).
        call(groups)
    end

    def subdependency_production_check
      !subdependency_metadata&.all? { |h| h[:production] == false }
    end

    def display_name
      display_name_builder =
        self.class.display_name_builder_for_package_manager(package_manager)
      return name unless display_name_builder

      display_name_builder.call(name)
    end

    def humanized_previous_version
      # If we don't have a previous version, we *may* still be able to figure
      # one out if a ref was provided and has been changed (in which case the
      # previous ref was essentially the version).
      if previous_version.nil?
        return ref_changed? ? previous_ref : nil
      end

      if previous_version.match?(/^[0-9a-f]{40}/)
        return previous_ref if ref_changed? && previous_ref

        "`#{previous_version[0..6]}`"
      elsif version == previous_version &&
            package_manager == "docker"
        digest = docker_digest_from_reqs(previous_requirements)
        "`#{digest.split(':').last[0..6]}`"
      else
        previous_version
      end
    end

    def humanized_version
      return if removed?

      if version.match?(/^[0-9a-f]{40}/)
        return new_ref if ref_changed? && new_ref

        "`#{version[0..6]}`"
      elsif version == previous_version &&
            package_manager == "docker"
        digest = docker_digest_from_reqs(requirements)
        "`#{digest.split(':').last[0..6]}`"
      else
        version
      end
    end

    def docker_digest_from_reqs(requirements)
      requirements.
        filter_map { |r| r.dig(:source, "digest") || r.dig(:source, :digest) }.
        first
    end

    def previous_ref
      previous_refs = previous_requirements.filter_map do |r|
        r.dig(:source, "ref") || r.dig(:source, :ref)
      end.uniq
      return previous_refs.first if previous_refs.count == 1
    end

    def new_ref
      new_refs = requirements.filter_map do |r|
        r.dig(:source, "ref") || r.dig(:source, :ref)
      end.uniq
      return new_refs.first if new_refs.count == 1
    end

    def ref_changed?
      previous_ref != new_ref
    end

    # Returns all detected versions of the dependency. Only ecosystems that
    # support this feature will return more than the current version.
    def all_versions
      all_versions = metadata[:all_versions]
      return [version].compact unless all_versions

      all_versions.filter_map(&:version)
    end

    # This dependency is being indirectly updated by an update to another
    # dependency. We don't need to try and update it ourselves but want to
    # surface it to the user in the PR.
    def informational_only?
      metadata[:information_only]
    end

    def ==(other)
      other.instance_of?(self.class) && to_h == other.to_h
    end

    def hash
      to_h.hash
    end

    def eql?(other)
      self == other
    end

    def specific_requirements
      requirements.select { |r| requirement_class.new(r[:requirement]).specific? }
    end

    def requirement_class
      Utils.requirement_class_for_package_manager(package_manager)
    end

    def version_class
      Utils.version_class_for_package_manager(package_manager)
    end

    def source_details(allowed_types: nil)
      sources = requirements.map { |requirement| requirement.fetch(:source) }.uniq.compact
      sources.select! { |source| allowed_types.include?(source[:type].to_s) } if allowed_types

      git = allowed_types == ["git"]

      if (git && sources.map { |s| s[:url] }.uniq.count > 1) || (!git && sources.count > 1)
        raise "Multiple sources! #{sources.join(', ')}"
      end

      sources.first
    end

    def source_type
      details = source_details
      return "default" if details.nil?

      details[:type] || details.fetch("type")
    end

    private

    def check_values
      raise ArgumentError, "blank strings must not be provided as versions" if [version, previous_version].any?("")

      check_requirement_fields
      check_subdependency_metadata
    end

    def check_requirement_fields
      requirement_fields = [requirements, previous_requirements].compact
      unless requirement_fields.all?(Array) &&
             requirement_fields.flatten.all?(Hash)
        raise ArgumentError, "requirements must be an array of hashes"
      end

      required_keys = %i(requirement file groups source)
      optional_keys = %i(metadata)
      unless requirement_fields.flatten.
             all? { |r| required_keys.sort == (r.keys - optional_keys).sort }
        raise ArgumentError, "each requirement must have the following " \
                             "required keys: #{required_keys.join(', ')}." \
                             "Optionally, it may have the following keys: " \
                             "#{optional_keys.join(', ')}."
      end

      return if requirement_fields.flatten.none? { |r| r[:requirement] == "" }

      raise ArgumentError, "blank strings must not be provided as requirements"
    end

    def check_subdependency_metadata
      return unless subdependency_metadata

      unless subdependency_metadata.is_a?(Array) &&
             subdependency_metadata.all?(Hash)
        raise ArgumentError, "subdependency_metadata must be an array of hashes"
      end
    end

    def symbolize_keys(hash)
      hash.keys.to_h { |k| [k.to_sym, hash[k]] }
    end
  end
end
