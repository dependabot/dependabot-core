# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/luarocks/native_helpers"
require "dependabot/luarocks/version"

module Dependabot
  module LuaRocks
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      def latest_version
        dependency_manifest.max_by { |k,v| k }[0]
      end

      def latest_resolvable_version
        latest_version
      end

      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't implemented for LuaRocks
        false
      end

      def updated_requirements
        dependency.requirements.map do |req|
          req.merge(requirement: latest_version)
        end
      end

      private

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      def latest_resolvable_version_with_no_unlock
        # Irrelevant, since Luarocks uses a single dependency file
        nil
      end

      def luarocks_manifest
        return @luarocks_manifest unless @luarocks_manifest.nil?

        response = Dependabot::RegistryClient.get(url: "https://luarocks.org/manifest")
        @luarocks_manifest = JSON.parse(response.body)
      end

      def dependency_manifest
        @dependency_manifest ||= luarocks_manifest["repository"][dependency.name]
      end
    end
  end
end

Dependabot::UpdateCheckers.
  register("luarocks", Dependabot::LuaRocks::UpdateChecker)
