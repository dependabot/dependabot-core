# typed: strict
# frozen_string_literal: true

require "set"
require "sorbet-runtime"

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Nuget
    class CacheManager
      extend T::Sig

      sig { returns(T::Boolean) }
      def self.caching_disabled?
        ENV["DEPENDABOT_NUGET_CACHE_DISABLED"] == "true"
      end

      sig { params(name: String).returns(T.untyped) }
      def self.cache(name)
        return {} if caching_disabled?

        @cache ||= T.let({}, T.nilable(T::Hash[String, T.untyped]))
        @cache[name] ||= {}
        @cache[name]
      end
    end
  end
end
