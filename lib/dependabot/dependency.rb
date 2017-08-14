# frozen_string_literal: true
module Dependabot
  class Dependency
    attr_reader :name, :version, :requirement, :package_manager, :groups,
                :previous_version

    def initialize(name:, version:, requirement:, package_manager:, groups:,
                   previous_version: nil)
      @name = name
      @version = version
      @requirement = requirement
      @previous_version = previous_version
      @package_manager = package_manager
      @groups = groups

      return if groups.instance_of?(Array)
      raise ArgumentError, "groups must be and array"
    end

    def to_h
      {
        "name" => name,
        "version" => version,
        "requirement" => requirement,
        "previous_version" => previous_version,
        "package_manager" => package_manager,
        "groups" => groups
      }
    end
  end
end
