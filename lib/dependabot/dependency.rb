# frozen_string_literal: true
module Dependabot
  class Dependency
    attr_reader :name, :version, :requirements, :package_manager,
                :previous_version, :previous_requirements

    def initialize(name:, requirements:, package_manager:, version: nil,
                   previous_version: nil, previous_requirements: nil)
      @name = name
      @version = version
      @requirements = requirements
      @previous_version = previous_version
      @previous_requirements = previous_requirements
      @package_manager = package_manager

      check_values
    end

    def check_values
      if [version, previous_version].any? { |v| v == "" }
        raise ArgumentError, "blank strings must not be provided as versions"
      end

      requirement_fields = [requirements, previous_requirements].compact
      unless requirement_fields.all? { |r| r.is_a?(Array) } &&
             requirement_fields.flatten.all? { |r| r.is_a?(Hash) }
        raise ArgumentError, "requirements must be an array of hashes"
      end

      required_keys = %i(requirement file groups)
      unless requirement_fields.flatten.
             all? { |r| (r.keys - required_keys).empty? }
        raise ArgumentError, "each requirement must have the following "\
                             "required keys: #{required_keys.join(', ')}."
      end

      return if requirement_fields.flatten.none? { |r| r[:requirement] == "" }
      raise ArgumentError, "blank strings must not be provided as requirements"
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
  end
end
