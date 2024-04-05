# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "digest"
require "bundler/lockfile_parser"

module Dependabot
  module Bundler
    class CachedLockfileParser
      extend T::Sig

      sig { params(lockfile_content: String).returns(::Bundler::LockfileParser) }
      def self.parse(lockfile_content)
        lockfile_hash = Digest::SHA256.hexdigest(lockfile_content)
        @cache ||= T.let({}, T.nilable(T::Hash[String, ::Bundler::LockfileParser]))
        return T.must(@cache[lockfile_hash]) if @cache.key?(lockfile_hash)

        @cache[lockfile_hash] = ::Bundler::LockfileParser.new(lockfile_content)
      end
    end
  end
end
