# frozen_string_literal: true

module Dependabot
  class Dependency
    attr_reader :name, :version, :requirements, :package_manager,
                :previous_version, :previous_requirements

    def initialize(name:, requirements:, package_manager:, version: nil,
                   previous_version: nil, previous_requirements: nil)
      @name = name
      @version = version
      @requirements = requirements.map { |req| symbolize_keys(req) }
      @previous_version = previous_version
      @previous_requirements =
        previous_requirements&.map { |req| symbolize_keys(req) }
      @package_manager = package_manager

      check_values
    end

    def top_level?
      requirements.any?
    end

    def to_h
      {
        "name" => name,
        "version" => version,
        "requirements" => requirements,
        "previous_version" => previous_version,
        "previous_requirements" => previous_requirements,
        "package_manager" => package_manager
      }
    end

    def appears_in_lockfile?
      previous_version || (version && previous_requirements.nil?)
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/PerceivedComplexity
    def production?
      return nil unless top_level?
      groups = requirements.flat_map { |r| r.fetch(:groups).map(&:to_s) }

      case package_manager
      when "hex" then groups.empty? || groups.any? { |g| g.include?("prod") }
      when "npm_and_yarn"
        groups.include?("optionalDependencies") ||
          groups.include?("dependencies")
      when "composer" then groups.include?("runtime")
      when "pip" then groups.empty? || groups.include?("default")
      when "bundler"
        groups.empty? ||
          groups.include?("runtime") ||
          groups.include?("default") ||
          groups.any? { |g| g.include?("prod") }
      else true
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/PerceivedComplexity

    def ==(other)
      other.instance_of?(self.class) && to_h == other.to_h
    end

    def hash
      to_h.hash
    end

    def eql?(other)
      self.==(other)
    end

    private

    def check_values
      if [version, previous_version].any? { |v| v == "" }
        raise ArgumentError, "blank strings must not be provided as versions"
      end

      requirement_fields = [requirements, previous_requirements].compact
      unless requirement_fields.all? { |r| r.is_a?(Array) } &&
             requirement_fields.flatten.all? { |r| r.is_a?(Hash) }
        raise ArgumentError, "requirements must be an array of hashes"
      end

      required_keys = %i(requirement file groups source)
      unless requirement_fields.flatten.
             all? { |r| required_keys.sort == r.keys.sort }
        raise ArgumentError, "each requirement must have the following "\
                             "required keys: #{required_keys.join(', ')}."
      end

      return if requirement_fields.flatten.none? { |r| r[:requirement] == "" }
      raise ArgumentError, "blank strings must not be provided as requirements"
    end

    def symbolize_keys(hash)
      Hash[hash.keys.map { |k| [k.to_sym, hash[k]] }]
    end
  end
end
