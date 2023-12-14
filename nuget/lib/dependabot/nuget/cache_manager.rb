# typed: true
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "set"

module Dependabot
  module Nuget
    class CacheManager
      def self.caching_disabled?
        ENV["DEPENDABOT_NUGET_CACHE_DISABLED"] == "true"
      end

      def self.cache(name)
        @cache ||= {}
        @cache[name] ||= {}
        @cache[name]
      end
    end
  end
end
