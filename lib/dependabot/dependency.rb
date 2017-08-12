# frozen_string_literal: true
module Dependabot
  class Dependency
    attr_reader :name, :version, :requirement, :previous_version,
                :package_manager

    def initialize(name:, package_manager:, previous_version: nil, version: nil,
                   requirement: nil)
      if version.nil? && requirement.nil?
        raise ArgumentError, "Either a version or requirement must be provided"
      end
      @name = name
      @version = Gem::Version.new(version) unless requirement
      @requirement = Gem::Requirement.new(requirement) unless version
      @previous_version = previous_version
      @package_manager = package_manager
    end

    def to_h
      {
        "name" => name,
        "version" => version.to_s,
        "requirement" => requirement.to_s,
        "previous_version" => previous_version,
        "package_manager" => package_manager
      }
    end
  end
end
