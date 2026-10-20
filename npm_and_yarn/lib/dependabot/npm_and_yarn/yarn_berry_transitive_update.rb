# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_parser/yarn_lock"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/requirement"

module Dependabot
  module NpmAndYarn
    class YarnBerryTransitiveUpdate
      extend T::Sig

      sig do
        params(
          dependency_name: String,
          current_version: T.nilable(String),
          target_version: String,
          lockfile_name: String,
          env: T.nilable(T::Hash[String, String])
        ).returns(T.nilable(String))
      end
      def self.updated_lockfile_content(dependency_name:, current_version:, target_version:, lockfile_name:, env: nil)
        return unless current_version

        resolutions = resolutions_for(dependency_name, current_version, target_version, lockfile_name)
        return if resolutions.empty?

        resolutions.each do |descriptor, resolution|
          Helpers.run_yarn_command(
            ["set", "resolution", descriptor, resolution],
            fingerprint: "set resolution <descriptor> <resolution>",
            env: (env || {}).merge("YARN_ENABLE_SCRIPTS" => "false")
          )
        end
        File.read(lockfile_name)
      end

      sig do
        params(dependency_name: String, current_version: String, target_version: String, lockfile_name: String)
          .returns(T::Array[[String, String]])
      end
      def self.resolutions_for(dependency_name, current_version, target_version, lockfile_name)
        file = DependencyFile.new(name: lockfile_name, content: File.read(lockfile_name))
        descriptors = FileParser::YarnLock.new(file).parsed.flat_map do |selectors, record|
          record.version == current_version ? selectors.split(", ") : []
        end
        descriptors.filter_map do |descriptor|
          name, selector = descriptor.split("@npm:", 2)
          next unless selector

          aliased_requirement = Requirement.parse_dep_string(selector)
          next unless (aliased_requirement&.fetch(:name) || name) == dependency_name

          resolution = aliased_requirement ? "npm:#{dependency_name}@#{target_version}" : "npm:#{target_version}"
          [descriptor, resolution]
        end
      end
      private_class_method :resolutions_for
    end
  end
end
