# typed: strict
# frozen_string_literal: true

module Bundler
  class SolveFailure < BundlerError; end

  class Fetcher
    class AuthenticationForbiddenError < HTTPError; end
  end

  module UI
    class Shell < Object; end
  end

  class EndpointSpecification
    # Sorbet's bundled initializer still describes the older five-argument API.
    sig do
      params(
        name: String,
        version: T.any(String, Gem::Version),
        platform: T.any(String, Gem::Platform),
        spec_fetcher: Fetcher,
        dependencies: T::Array[T::Array[T.anything]],
        metadata: T.nilable(T::Array[T::Array[T.anything]])
      ).returns(EndpointSpecification)
    end
    def self.new(name, version, platform, spec_fetcher, dependencies, metadata = nil); end # rubocop:disable Metrics/ParameterLists -- Mirrors Bundler's constructor.

    sig { returns(T.nilable(Checksum)) }
    def checksum; end
  end
end
