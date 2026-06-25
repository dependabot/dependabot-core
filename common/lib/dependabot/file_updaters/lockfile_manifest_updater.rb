# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module FileUpdaters
    module LockfileManifestUpdater
      extend T::Sig
      extend T::Helpers

      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def lockfile_only_manifest_update?(file)
        new_version = dependency.version
        return false unless lockfile && new_version

        dependency.requirements.zip(T.must(dependency.previous_requirements)).any? do |new_req, old_req|
          previous_requirement = old_req&.fetch(:requirement)
          next false if new_req == old_req || new_req[:file] != file.name
          next false if new_req.dig(:source, :type) != "provider" || previous_requirement.nil?

          dependency.requirement_class
                    .new(previous_requirement)
                    .satisfied_by?(dependency.version_class.new(new_version))
        end
      end
    end
  end
end
