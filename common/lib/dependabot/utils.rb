# typed: strong
# frozen_string_literal: true

require "tmpdir"
require "set"
require "sorbet-runtime"

require "dependabot/version"

# TODO: in due course, these "registries" should live in a wrapper gem, not
#       dependabot-core.
module Dependabot
  module Utils
    extend T::Sig

    BUMP_TMP_FILE_PREFIX = "dependabot_"
    BUMP_TMP_DIR_PATH = T.let(File.expand_path(Dir::Tmpname.create("", "tmp") { nil }), String)

    @version_classes = T.let({}, T::Hash[String, T.class_of(Dependabot::Version)])

    sig { params(package_manager: String).returns(T.class_of(Dependabot::Version)) }
    def self.version_class_for_package_manager(package_manager)
      version_class = @version_classes[package_manager]
      return version_class if version_class

      raise "Unsupported package_manager #{package_manager}"
    end

    sig { params(package_manager: String, version_class: T.class_of(Dependabot::Version)).void }
    def self.register_version_class(package_manager, version_class)
      @version_classes[package_manager] = version_class
    end

    @requirement_classes = T.let({}, T::Hash[String, T.class_of(Gem::Requirement)])

    sig { params(package_manager: String).returns(T.class_of(Gem::Requirement)) }
    def self.requirement_class_for_package_manager(package_manager)
      requirement_class = @requirement_classes[package_manager]
      return requirement_class if requirement_class

      raise "Unsupported package_manager #{package_manager}"
    end

    sig { params(package_manager: String, requirement_class: T.class_of(Gem::Requirement)).void }
    def self.register_requirement_class(package_manager, requirement_class)
      @requirement_classes[package_manager] = requirement_class
    end

    @cloning_package_managers = T.let(Set[], T::Set[String])

    sig { params(package_manager: String).returns(T::Boolean) }
    def self.always_clone_for_package_manager?(package_manager)
      @cloning_package_managers.include?(package_manager)
    end

    sig { params(package_manager: String).void }
    def self.register_always_clone(package_manager)
      @cloning_package_managers << package_manager
    end
  end
end
