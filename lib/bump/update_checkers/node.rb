# frozen_string_literal: true
require "json"
require "excon"
require "bump/update_checkers/base"

module Bump
  module UpdateCheckers
    class Node < Base
      def latest_version
        @latest_version ||=
          begin
            JSON.parse(Excon.get(dependency_url).body)["dist-tags"]["latest"]
          end
      end

      def dependency_version
        Gem::Version.new(dependency.version)
      end

      private

      def dependency_url
        path = dependency.name.gsub("/", "%2F")
        "http://registry.npmjs.org/#{path}"
      end

      def language
        "node"
      end
    end
  end
end
