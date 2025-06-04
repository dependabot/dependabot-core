# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/npm_and_yarn/file_updater"
require "dependabot/npm_and_yarn/file_parser"

module Dependabot
  module NpmAndYarn
    class FileUpdater < Dependabot::FileUpdaters::Base
      class PackageJsonPreparer
        extend T::Sig

        sig { params(package_json_content: String).void }
        def initialize(package_json_content:)
          @package_json_content = package_json_content
        end

        sig { returns(String) }
        def prepared_content
          content = package_json_content
          content = replace_ssh_sources(content)
          content = remove_workspace_path_prefixes(content)
          content = remove_invalid_characters(content)
          content
        end

        sig { params(content: String).returns(String) }
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
        sig { params(content: String).returns(String) }
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

        sig { params(content: String).returns(String) }
        def remove_invalid_characters(content)
          content
            .gsub(/\{\{[^\}]*?\}\}/, "something") # {{ nm }} syntax not allowed
            .gsub(/(?<!\\)\\ /, " ") # escaped whitespace not allowed
            .gsub(%r{^\s*//.*}, " ") # comments are not allowed
        end

        sig { returns(T::Array[String]) }
        def swapped_ssh_requirements
          git_ssh_requirements_to_swap
        end

        private

        sig { returns(String) }
        attr_reader :package_json_content

        sig { returns(T::Array[String]) }
        def git_ssh_requirements_to_swap
          return @git_ssh_requirements_to_swap if @git_ssh_requirements_to_swap

          @git_ssh_requirements_to_swap = T.let([], T.nilable(T::Array[String]))

          NpmAndYarn::FileParser.each_dependency(JSON.parse(package_json_content)) do |_, req, _t|
            next unless req.is_a?(String)
            next unless req.start_with?("git+ssh:")

            req = req.split("#").first
            T.must(@git_ssh_requirements_to_swap) << T.must(req)
          end

          T.must(@git_ssh_requirements_to_swap)
        end
      end
    end
  end
end
