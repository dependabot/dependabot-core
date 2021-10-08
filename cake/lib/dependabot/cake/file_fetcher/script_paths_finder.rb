# frozen_string_literal: true

require "pathname"

module Dependabot
  module Cake
    class FileFetcher
      class ScriptPathsFinder
        require_relative "wildcard_search"

        def initialize(cake_file:)
          @cake_file = cake_file
        end

        def import_paths(base_path:, wildcard_search:)
          paths = []

          @cake_file.content.each_line do |line|
            # Details of Cake preprocessor directives is at
            # https://cakebuild.net/docs/fundamentals/preprocessor-directives
            # @examples Load Directive
            #    #load "scripts/utilities.cake"
            #    #l "local:?path=scripts/utilities.cake"
            directive = Directives.parse_cake_directive_from(line)
            next if directive.nil?
            next unless supported_type?(directive.type)
            next unless supported_scheme?(directive.scheme)
            next unless directive.query.key?(:path)

            path = directive.query[:path]
            next unless path.end_with?(".cake")

            paths << if WildcardSearch.wildcard_search?(path)
                       wildcard_search.perform_search(base_path, path)
                     else
                       # Script file is relative to parsed script location
                       directory = File.dirname(@cake_file.name)
                       path = Pathname.new(directory + "/" + path).
                              cleanpath.to_path
                       path
                     end
          end
          paths.flatten
        end

        private

        def supported_type?(type)
          %w(load).include?(type)
        end

        def supported_scheme?(scheme)
          %w(local).include?(scheme)
        end
      end
    end
  end
end
