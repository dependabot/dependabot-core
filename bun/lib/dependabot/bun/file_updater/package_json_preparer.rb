# typed: true
# frozen_string_literal: true

require "dependabot/npm_and_yarn/file_updater"
require "dependabot/npm_and_yarn/file_parser"

module Dependabot
  module NpmAndYarn
    class FileUpdater < Dependabot::FileUpdaters::Base
      class PackageJsonPreparer
        def initialize(package_json_content:)
          @package_json_content = package_json_content
        end

        def prepared_content
          content = package_json_content
          content = replace_ssh_sources(content)
          content = remove_workspace_path_prefixes(content)
          content = remove_invalid_characters(content)
          content
        end

        def replace_ssh_sources(content)
          updated_content = content

          git_ssh_requirements_to_swap.each do |req|
            new_req = req.gsub(%r{git\+ssh://git@(.*?)[:/]}, 'https://\1/')
            updated_content = updated_content.gsub(req, new_req)
          end

          updated_content
        end

        # A bug prevents Yarn recognising that a directory is part of a
        # workspace if it is specified with a `./` prefix.
        def remove_workspace_path_prefixes(content)
          json = JSON.parse(content)
          return content unless json.key?("workspaces")

          workspace_object = json.fetch("workspaces")
          paths_array =
            if workspace_object.is_a?(Hash)
              workspace_object.values_at("packages", "nohoist")
                              .flatten.compact
            elsif workspace_object.is_a?(Array) then workspace_object
            else
              raise "Unexpected workspace object"
            end

          paths_array.each { |path| path.gsub!(%r{^\./}, "") }

          JSON.pretty_generate(json)
        end

        def remove_invalid_characters(content)
          content
            .gsub(/\{\{[^\}]*?\}\}/, "something") # {{ nm }} syntax not allowed
            .gsub(/(?<!\\)\\ /, " ") # escaped whitespace not allowed
            .gsub(%r{^\s*//.*}, " ") # comments are not allowed
        end

        def swapped_ssh_requirements
          git_ssh_requirements_to_swap
        end

        private

        attr_reader :package_json_content

        def git_ssh_requirements_to_swap
          return @git_ssh_requirements_to_swap if @git_ssh_requirements_to_swap

          @git_ssh_requirements_to_swap = []

          NpmAndYarn::FileParser.each_dependency(JSON.parse(package_json_content)) do |_, req, _t|
            next unless req.is_a?(String)
            next unless req.start_with?("git+ssh:")

            req = req.split("#").first
            @git_ssh_requirements_to_swap << req
          end

          @git_ssh_requirements_to_swap
        end
      end
    end
  end
end
