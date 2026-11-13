# typed: strong
# frozen_string_literal: true

require "dependabot/errors"
require "sorbet-runtime"

module Dependabot
  module Clients
    module GithubResourceParser
      extend T::Sig

      private

      sig { params(resource: Sawyer::Resource, key: Symbol, context: String).returns(String) }
      def github_string(resource, key, context)
        value = T.cast(resource[key], Object)
        return value if value.is_a?(String)

        raise_bad_github_response("#{context} #{key} must be a string")
      end

      sig { params(resource: Sawyer::Resource, key: Symbol, context: String).returns(T.nilable(String)) }
      def github_optional_string(resource, key, context)
        value = T.cast(resource[key], Object)
        return if value.nil?
        return value if value.is_a?(String)

        raise_bad_github_response("#{context} #{key} must be a string or nil")
      end

      sig { params(resource: Sawyer::Resource, key: Symbol, context: String).returns(Integer) }
      def github_integer(resource, key, context)
        value = T.cast(resource[key], Object)
        return value if value.is_a?(Integer)

        raise_bad_github_response("#{context} #{key} must be an integer")
      end

      sig { params(resource: Sawyer::Resource, key: Symbol, context: String).returns(T::Boolean) }
      def github_boolean(resource, key, context)
        value = T.cast(resource[key], Object)
        return value if value == true
        return false if value.nil? || value == false

        raise_bad_github_response("#{context} #{key} must be a boolean or nil")
      end

      sig { params(resource: Sawyer::Resource, key: Symbol, context: String).returns(Sawyer::Resource) }
      def github_resource(resource, key, context)
        value = T.cast(resource[key], Object)
        return value if value.is_a?(Sawyer::Resource)

        raise_bad_github_response("#{context} #{key} must be an object")
      end

      sig { params(message: String).returns(T.noreturn) }
      def raise_bad_github_response(message)
        Kernel.raise Dependabot::PrivateSourceBadResponse.new(
          github_response_source,
          "Malformed GitHub response: #{message}"
        )
      end

      sig { returns(String) }
      def github_response_source
        Kernel.raise NotImplementedError
      end
    end
  end
end
