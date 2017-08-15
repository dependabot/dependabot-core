# frozen_string_literal: true
module Dependabot
  class Dependency
    attr_reader :name, :version, :requirement, :package_manager, :groups,
                :previous_version, :previous_requirement

    def initialize(name:, requirement:, package_manager:, groups:, version: nil,
                   previous_version: nil, previous_requirement: nil)
      @name = name
      @version = version
      @requirement = requirement
      @previous_version = previous_version
      @previous_requirement = previous_requirement
      @package_manager = package_manager
      @groups = groups

      check_values
    end

    def check_values
      unless groups.instance_of?(Array)
        raise ArgumentError, "groups must be and array"
      end

      if [version, previous_version].any? { |v| v == "" }
        raise ArgumentError, "blank strings must not be provided as versions"
      end

      return unless [requirement, previous_requirement].any? { |r| r == "" }
      raise ArgumentError, "blank strings must not be provided as requirements"
    end

    def to_h
      {
        "name" => name,
        "version" => version,
        "requirement" => requirement,
        "previous_version" => previous_version,
        "previous_requirement" => previous_requirement,
        "package_manager" => package_manager,
        "groups" => groups
      }
    end
  end
end
