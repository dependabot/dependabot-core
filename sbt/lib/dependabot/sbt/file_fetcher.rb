# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Sbt
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      BUILD_SBT_FILENAME = "build.sbt"
      PLUGINS_SBT_FILENAME = "project/plugins.sbt"
      BUILD_PROPERTIES_FILENAME = "project/build.properties"

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |name| name.end_with?(BUILD_SBT_FILENAME) }
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a build.sbt file."
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        unless allow_beta_ecosystems?
          raise Dependabot::DependencyFileNotFound.new(
            nil,
            "Sbt support is currently in beta. Enable the beta ecosystems experiment to use it " \
            "(for example, run bin/dry-run.rb --enable-beta-ecosystems)."
          )
        end

        fetched_files = T.let([], T::Array[DependencyFile])

        fetched_files << build_sbt
        fetched_files << T.must(plugins_sbt) if plugins_sbt
        fetched_files << T.must(build_properties) if build_properties
        fetched_files += subproject_build_files

        fetched_files
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def ecosystem_versions
        return nil unless build_properties

        sbt_version = T.must(build_properties).content&.match(/sbt\.version\s*=\s*(.+)/)&.captures&.first&.strip
        return nil unless sbt_version

        {
          package_managers: {
            "sbt" => sbt_version
          }
        }
      end

      private

      sig { returns(DependencyFile) }
      def build_sbt
        @build_sbt ||= T.let(fetch_file_from_host(BUILD_SBT_FILENAME), T.nilable(DependencyFile))
      end

      sig { returns(T.nilable(DependencyFile)) }
      def plugins_sbt
        @plugins_sbt ||= T.let(fetch_file_if_present(PLUGINS_SBT_FILENAME), T.nilable(DependencyFile))
      end

      sig { returns(T.nilable(DependencyFile)) }
      def build_properties
        @build_properties ||= T.let(fetch_file_if_present(BUILD_PROPERTIES_FILENAME), T.nilable(DependencyFile))
      end

      sig { returns(T::Array[DependencyFile]) }
      def subproject_build_files
        repo_contents(raise_errors: false)
          .select { |item| item.type == "dir" }
          .filter_map { |dir| fetch_subproject_build_sbt(dir.name) }
      end

      sig { params(dir_name: String).returns(T.nilable(DependencyFile)) }
      def fetch_subproject_build_sbt(dir_name)
        fetch_file_if_present(File.join(dir_name, BUILD_SBT_FILENAME))
      end
    end
  end
end

Dependabot::FileFetchers.register("sbt", Dependabot::Sbt::FileFetcher)
