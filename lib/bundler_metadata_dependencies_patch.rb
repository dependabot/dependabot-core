# frozen_string_literal: true
module Bundler
  class Resolver
    class SpecGroup
      private

      # Bundler uses StubSpecification specs for dependencies that are currently
      # installed, and doesn't add Ruby/Rubygems details to them. That makes
      # sense for a normal user, who wouldn't have the gem version installed
      # if it wasn't compatible with their Ruby version. It doesn't make sense
      # for Dependabot, since we may have the gem in our own Gemfile but be
      # updating it for another Gemfile that specifies a different Ruby version.
      #
      # Fix is to monkey patch Bundler to add Ruby/Rubygems details to
      # StubSpecification specs.
      #
      # rubocop:disable all
      def metadata_dependencies(spec, platform)
        return [] unless spec
        return [] if !spec.is_a?(Gem::Specification) && !spec.is_a?(Bundler::StubSpecification)
        dependencies = []
        if !spec.required_ruby_version.nil? && !spec.required_ruby_version.none?
          dependencies << DepProxy.new(Gem::Dependency.new("ruby\0", spec.required_ruby_version), platform)
        end
        if !spec.required_rubygems_version.nil? && !spec.required_rubygems_version.none?
          dependencies << DepProxy.new(Gem::Dependency.new("rubygems\0", spec.required_rubygems_version), platform)
        end
        dependencies
      end
      # rubocop:enable
    end
  end
end
