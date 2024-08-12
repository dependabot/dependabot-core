# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class PackageManagerBase
    extend T::Sig
    extend T::Helpers

    abstract!

    # The name of the package manager (e.g., "bundler")
    sig { abstract.returns(String) }
    def name; end

    # The version of the package manager (e.g., "2.1.4")
    sig { abstract.returns(T.nilable(String)) }
    def version; end

    # The major version of the package manager (e.g., "2")
    sig { returns(T.nilable(String)) }
    def major_version
      version&.split(".")&.first
    end

    sig { returns(T.nilable(T::Array[String])) }
    def deprecated_versions
      nil
    end

    sig { returns(T.nilable(T::Array[String])) }
    def unsupported_versions
      nil
    end

    sig { returns(T.nilable(T::Array[String])) }
    def supported_versions
      nil
    end

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
