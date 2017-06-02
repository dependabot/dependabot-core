# frozen_string_literal: true
module Dependabot
  class Dependency
    attr_reader :name, :version, :previous_version, :package_manager

    def initialize(name:, version:, package_manager:, previous_version: nil)
      @name = name
      @version = version
      @previous_version = previous_version
      @package_manager = package_manager
    end

    def to_h
      {
        "name" => name,
        "version" => version,
        "previous_version" => previous_version,
        "package_manager" => package_manager
      }
    end
  end
end
