# typed: strict
# frozen_string_literal: true

module Bundler
  class Checksum
    sig { params(algo: String, digest: String, source: Source).void }
    def initialize(algo, digest, source); end

    sig { params(other: Checksum).returns(T.nilable(Checksum)) }
    def merge!(other); end

    class Source
      sig { params(type: Symbol, location: String).void }
      def initialize(type, location); end
    end
  end

  class ChecksumMismatchError < SecurityError
    sig { params(lock_name: String, existing: Checksum, checksum: Checksum).void }
    def initialize(lock_name, existing, checksum); end
  end
end
