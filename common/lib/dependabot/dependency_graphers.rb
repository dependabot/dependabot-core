# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_graphers/base"
require "dependabot/dependency_graphers/generic"

module Dependabot
  module DependencyGraphers
    extend T::Sig

    @graphers = T.let({}, T::Hash[String, T.class_of(Base)])

    sig { params(package_manager: String).returns(T.class_of(Base)) }
    def self.for_package_manager(package_manager)
      grapher = @graphers[package_manager]
      return grapher if grapher

      # If an ecosystem has not defined its own graphing strategy, then we use
      # a best-effort generic while we are rolling out graphing capabilities.
      #
      # This approach allows us to assess the quality of data from the ecosystem's
      # parser and triage the scope of work to implement the non-generic class.
      Generic
    end

    sig { params(package_manager: String, grapher: T.class_of(Base)).void }
    def self.register(package_manager, grapher)
      @graphers[package_manager] = grapher
    end
  end
end
