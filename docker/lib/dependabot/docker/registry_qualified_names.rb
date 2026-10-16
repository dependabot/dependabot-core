# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"

module Dependabot
  module Docker
    # Image dependencies are named without their registry host (e.g.
    # `dotnet/sdk` for `mcr.microsoft.com/dotnet/sdk`). This lets group, allow
    # and ignore patterns also match the image name as written in the manifest.
    module RegistryQualifiedNames
      extend T::Sig

      sig { params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def self.for(dependency)
        dependency.requirements.filter_map do |requirement|
          registry = requirement.source_string("registry")
          "#{registry}/#{dependency.name}" if registry && !registry.empty?
        end
      end

      BUILDER = T.let(
        ->(dependency) { self.for(dependency) },
        T.proc.params(arg0: Dependabot::Dependency).returns(T::Array[String])
      )
    end
  end
end
