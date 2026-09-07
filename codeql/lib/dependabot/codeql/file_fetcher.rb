# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Codeql
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?("qlpack.yml")
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a qlpack.yml file."
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_files
        files = [qlpack_file]
        files << lockfile if lockfile

        files.compact
      end

      private

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def qlpack_file
        @qlpack_file ||= T.let(fetch_file_if_present("qlpack.yml"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(fetch_file_if_present("codeql-pack.lock.yml"), T.nilable(Dependabot::DependencyFile))
      end
    end
  end
end

Dependabot::FileFetchers.register("codeql", Dependabot::Codeql::FileFetcher)
