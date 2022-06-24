# frozen_string_literal: true

require "rubygems_version_patch"

module Dependabot
  class SecurityAdvisory
    attr_reader :dependency_name, :package_manager,
                :vulnerable_versions, :safe_versions,
                :vulnerable_version_strings

    def initialize(dependency_name:, package_manager:,
                   vulnerable_versions: [], safe_versions: [])
      @dependency_name = dependency_name
      @package_manager = package_manager
      @vulnerable_version_strings = vulnerable_versions || []
      @vulnerable_versions = []
      @safe_versions = safe_versions || []

      convert_string_version_requirements
      check_version_requirements
    end

    def vulnerable?(version)
      unless version.is_a?(version_class) || version.instance_of?(Gem::Version)
        raise ArgumentError, "must be a #{version_class}"
      end

      in_safe_range = safe_versions.
                      any? { |r| r.satisfied_by?(version) }

      # If version is known safe for this advisory, it's not vulnerable
      return false if in_safe_range

      in_vulnerable_range = vulnerable_versions.
                            any? { |r| r.satisfied_by?(version) }

      # If in the vulnerable range and not known safe, it's vulnerable
      return true if in_vulnerable_range

      # If a vulnerable range present but not met, it's not vulnerable
      return false if vulnerable_versions.any?

      # Finally, if no vulnerable range provided, but a safe range provided,
      # and this versions isn't included (checked earlier), it's vulnerable
      safe_versions.any?
    end

    # Check if the advisory is fixed by the updated dependency
    #
    # @param dependency [Dependabot::Dependency] Updated dependency
    # @return [Boolean]
    def fixed_by?(dependency)
      # Handle case mismatch between the security advisory and parsed name
      return false unless dependency_name.downcase == dependency.name.downcase
      return false unless package_manager == dependency.package_manager
      # TODO: Support no previous version to the same level as dependency graph
      # and security alerts. We currently ignore dependency updates without a
      # previous version because we don't know if the dependency was vulerable.
      return false unless dependency.previous_version
      return false unless version_class.correct?(dependency.previous_version)

      # Ignore deps that weren't previously vulnerable
      return false unless affects_version?(dependency.previous_version)

      # Select deps that are now fixed
      !affects_version?(dependency.version)
    end

    # Check if the version is affected by the advisory
    #
    # @param version [Dependabot::<Package Manager>::Version] version class
    # @return [Boolean]
    def affects_version?(version)
      return false unless version_class.correct?(version)
      return false unless [*safe_versions, *vulnerable_versions].any?

      version = version_class.new(version)

      # If version is known safe for this advisory, it's not vulnerable
      return false if safe_versions.any? { |r| r.satisfied_by?(version) }

      # If in the vulnerable range and not known safe, it's vulnerable
      return true if vulnerable_versions.any? { |r| r.satisfied_by?(version) }

      # If a vulnerable range present but not met, it's not vulnerable
      return false if vulnerable_versions.any?

      # Finally, if no vulnerable range provided, but a safe range provided,
      # and this versions isn't included (checked earler), it's vulnerable
      safe_versions.any?
    end

    private

    def convert_string_version_requirements
      @vulnerable_versions = vulnerable_version_strings.flat_map do |vuln_str|
        next vuln_str unless vuln_str.is_a?(String)

        requirement_class.requirements_array(vuln_str)
      end

      @safe_versions = safe_versions.flat_map do |safe_str|
        next safe_str unless safe_str.is_a?(String)

        requirement_class.requirements_array(safe_str)
      end
    end

    def check_version_requirements
      unless vulnerable_versions.is_a?(Array) &&
             vulnerable_versions.all? { |i| requirement_class <= i.class }
        raise ArgumentError, "vulnerable_versions must be an array "\
                             "of #{requirement_class} instances"
      end

      unless safe_versions.is_a?(Array) &&
             safe_versions.all? { |i| requirement_class <= i.class }
        raise ArgumentError, "safe_versions must be an array "\
                             "of #{requirement_class} instances"
      end
    end

    def version_class
      Utils.version_class_for_package_manager(package_manager)
    end

    def requirement_class
      Utils.requirement_class_for_package_manager(package_manager)
    end
  end
end
