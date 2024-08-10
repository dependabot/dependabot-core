# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class PackageManagerBase
    extend T::Sig
    extend T::Helpers

    abstract!

    sig { abstract.returns(String) }
    def name; end

    sig { abstract.returns(String) }
    def version; end

    sig { abstract.returns(T.nilable(T::Array[String])) }
    def deprecated_versions; end

    sig { abstract.returns(T.nilable(T::Array[String])) }
    def unsupported_versions; end

    sig { abstract.returns(T.nilable(T::Array[String])) }
    def supported_versions; end

    sig { returns(T::Boolean) }
    def deprecated
      deprecated_versions&.include?(version) || false
    end

    sig { returns(T::Boolean) }
    def unsupported
      unsupported_versions&.include?(version) || false
    end
  end
end
