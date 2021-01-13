# frozen_string_literal: true

require "set"

# TODO: in due course, these "registries" should live in a wrapper gem, not
#       dependabot-core.
module Dependabot
  module Utils
    BUMP_TMP_FILE_PREFIX = "dependabot_"
    BUMP_TMP_DIR_PATH = "tmp"

    @version_classes = {}

    def self.version_class_for_package_manager(package_manager)
      version_class = @version_classes[package_manager]
      return version_class if version_class

      raise "Unsupported package_manager #{package_manager}"
    end

    def self.register_version_class(package_manager, version_class)
      @version_classes[package_manager] = version_class
    end

    @requirement_classes = {}

    def self.requirement_class_for_package_manager(package_manager)
      requirement_class = @requirement_classes[package_manager]
      return requirement_class if requirement_class

      raise "Unsupported package_manager #{package_manager}"
    end

    def self.register_requirement_class(package_manager, requirement_class)
      @requirement_classes[package_manager] = requirement_class
    end

    @cloning_package_managers = Set[]

    def self.always_clone_for_package_manager?(package_manager)
      @cloning_package_managers.include?(package_manager)
    end

    def self.register_always_clone(package_manager)
      @cloning_package_managers << package_manager
    end
  end
end
