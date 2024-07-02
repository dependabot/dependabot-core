# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

# For details on pub packages, see:
# https://dart.dev/tools/pub/package-layout#the-pubspec
module Dependabot
  module Pub
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?("pubspec.yaml")
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a pubspec.yaml."
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = []
        fetched_files << pubspec_yaml
        fetched_files << pubspec_lock if pubspec_lock
        # Fetch any additional pubspec.yamls in the same git repo for resolving
        # local path-dependencies.
        extra_pubspecs = Dir.glob("**/pubspec.yaml", base: clone_repo_contents)
        fetched_files += extra_pubspecs.map do |pubspec|
          relative_name = Pathname.new("/#{pubspec}").relative_path_from(directory)
          fetch_file_from_host(relative_name)
        end
        fetched_files.uniq
      end

      private

      sig { returns(DependencyFile) }
      def pubspec_yaml
        @pubspec_yaml ||= T.let(fetch_file_from_host("pubspec.yaml"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(DependencyFile)) }
      def pubspec_lock
        return @pubspec_lock if defined?(@pubspec_lock)

        @pubspec_lock = T.let(fetch_file_if_present("pubspec.lock"), T.nilable(Dependabot::DependencyFile))
      end
    end
  end
end

Dependabot::FileFetchers.register("pub", Dependabot::Pub::FileFetcher)
