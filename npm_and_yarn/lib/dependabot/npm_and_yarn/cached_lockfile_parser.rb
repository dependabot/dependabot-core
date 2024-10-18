# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "digest"
require "digest/sha2"
require "dependabot/npm_and_yarn/file_parser/lockfile_parser"

module Dependabot
  module NpmAndYarn
    class CachedLockfileParser
      extend T::Sig

      sig do
        params(dependency_files: T::Array[Dependabot::DependencyFile]).returns(
          Dependabot::NpmAndYarn::FileParser::LockfileParser
        )
      end
      def self.parse(dependency_files:)
        lockfile_content = dependency_files.map(&:content).join
        lockfile_hash = Digest::SHA2.hexdigest(lockfile_content)
        @cache ||= T.let({}, T.nilable(T::Hash[String, Dependabot::NpmAndYarn::FileParser::LockfileParser]))
        return T.must(@cache[lockfile_hash]) if @cache.key?(lockfile_hash)

        @cache[lockfile_hash] =
          Dependabot::NpmAndYarn::FileParser::LockfileParser.new(dependency_files: dependency_files)
      end
    end
  end
end
