# frozen_string_literal: true

require "bundler/endpoint_specification"

module EndpointSpecificationPatch
  def required_ruby_version
    @required_ruby_version ||= Gem::Requirement.default
  end

  def required_rubygems_version
    @required_rubygems_version ||= Gem::Requirement.default
  end
end

Bundler::EndpointSpecification.prepend(EndpointSpecificationPatch)
