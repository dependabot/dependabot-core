# frozen_string_literal: true

require "bundler"
require "parser/current"

require "bundler_definition_version_patch"
require "bundler_git_source_patch"

require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/file_updaters/base"
require "dependabot/update_checkers/ruby/bundler/file_preparer"

module Dependabot
  module FileUpdaters
    module Ruby
      class Bundler < Dependabot::FileUpdaters::Base
        LOCKFILE_ENDING = /(?<ending>\s*(?:RUBY VERSION|BUNDLED WITH).*)/m
        DEPENDENCY_DECLARATION_REGEX =
          /^\s*\w*\.add(?:_development|_runtime)?_dependency
            (\s*|\()['"](?<name>.*?)['"],
            \s*(?<requirements>.*?)\)?\s*$/x

        def self.updated_files_regex
          [
            /^Gemfile$/,
            /^Gemfile\.lock$/,
            %r{^[^/]*\.gemspec$}
          ]
        end

        # rubocop:disable Metrics/CyclomaticComplexity
        def updated_dependency_files
          updated_files = []

          if gemfile && gemfile_changed?
            updated_files <<
              updated_file(file: gemfile, content: updated_gemfile_content)
          end

          if lockfile && dependency.appears_in_lockfile?
            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)
          end

          if gemspec && gemspec_changed?
            updated_files <<
              updated_file(file: gemspec, content: updated_gemspec_content)
          end

          updated_files
        end
        # rubocop:enable Metrics/CyclomaticComplexity

        private

        def check_required_files
          file_names = dependency_files.map(&:name)

          if file_names.include?("Gemfile.lock") &&
             !file_names.include?("Gemfile")
            raise "A Gemfile must be provided if a lockfile is!"
          end

          return if file_names.any? { |name| name.match?(%r{^[^/]*\.gemspec$}) }
          return if file_names.include?("Gemfile")

          raise "A gemspec or Gemfile must be provided!"
        end

        def gemfile
          @gemfile ||= get_original_file("Gemfile")
        end

        def lockfile
          @lockfile ||= get_original_file("Gemfile.lock")
        end

        def gemfile_changed?
          changed_requirements =
            dependency.requirements - dependency.previous_requirements

          changed_requirements.any? { |f| f[:file] == "Gemfile" }
        end

        def gemspec_changed?
          changed_requirements =
            dependency.requirements - dependency.previous_requirements

          changed_requirements.any? { |f| f[:file].end_with?(".gemspec") }
        end

        def remove_git_source?
          old_gemfile_req =
            dependency.previous_requirements.find { |f| f[:file] == "Gemfile" }
          return false unless old_gemfile_req&.dig(:source, :type) == "git"

          new_gemfile_req =
            dependency.requirements.find { |f| f[:file] == "Gemfile" }

          new_gemfile_req[:source].nil?
        end

        def updated_gemfile_content
          content = replace_gemfile_version_requirement(gemfile.content)
          content = remove_gemfile_git_source(content) if remove_git_source?
          content
        end

        def updated_gemspec_content
          replace_gemspec_version_requirement(gemspec.content)
        end

        def replace_gemfile_version_requirement(content)
          buffer = Parser::Source::Buffer.new("(gemfile_content)")
          buffer.source = content
          ast = Parser::CurrentRuby.new.parse(buffer)

          ReplaceRequirement.
            new(dependency: dependency, filename: gemfile.name).
            rewrite(buffer, ast)
        end

        def remove_gemfile_git_source(content)
          buffer = Parser::Source::Buffer.new("(gemfile_content)")
          buffer.source = content
          ast = Parser::CurrentRuby.new.parse(buffer)

          UpdateCheckers::Ruby::Bundler::FilePreparer::RemoveGitSource.
            new(dependency: dependency).
            rewrite(buffer, ast)
        end

        def replace_gemspec_version_requirement(content)
          buffer = Parser::Source::Buffer.new("(gemspec_content)")
          buffer.source = content
          ast = Parser::CurrentRuby.new.parse(buffer)

          ReplaceRequirement.
            new(dependency: dependency, filename: gemspec.name).
            rewrite(buffer, ast)
        end

        def updated_lockfile_content
          @updated_lockfile_content ||= build_updated_lockfile
        end

        def build_updated_lockfile
          lockfile_body =
            SharedHelpers.in_a_temporary_directory do |tmp_dir|
              write_temporary_dependency_files

              SharedHelpers.in_a_forked_process do
                ::Bundler.instance_variable_set(:@root, tmp_dir)
                # Remove installed gems from the default Rubygems index
                ::Gem::Specification.all = []

                # Set auth details for GitHub
                ::Bundler.settings.set_command_option(
                  "github.com",
                  "x-access-token:#{github_access_token}"
                )

                definition = ::Bundler::Definition.build(
                  "Gemfile",
                  "Gemfile.lock",
                  gems: [dependency.name]
                )
                definition.resolve_remotely!
                definition.to_lock
              end
            end
          post_process_lockfile(lockfile_body)
        end

        def write_temporary_dependency_files
          File.write(
            "Gemfile",
            updated_gemfile_content
          )
          File.write(
            "Gemfile.lock",
            lockfile.content
          )

          if gemspec
            File.write(
              gemspec.name,
              sanitized_gemspec_content(updated_gemspec)
            )
          end

          write_ruby_version_file

          path_gemspecs.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, sanitized_gemspec_content(file))
          end
        end

        def write_ruby_version_file
          return unless ruby_version_file
          path = ruby_version_file.name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, ruby_version_file.content)
        end

        def path_gemspecs
          all = dependency_files.select { |f| f.name.end_with?(".gemspec") }
          all - [gemspec]
        end

        def gemspec
          dependency_files.find { |f| f.name.match?(%r{^[^/]*\.gemspec$}) }
        end

        def updated_gemspec
          updated_file(file: gemspec, content: updated_gemspec_content)
        end

        def ruby_version_file
          dependency_files.find { |f| f.name == ".ruby-version" }
        end

        def post_process_lockfile(lockfile_body)
          # Re-add the old `BUNDLED WITH` version (and remove the RUBY VERSION
          # if it wasn't previously present in the lockfile)
          lockfile_body.gsub(
            LOCKFILE_ENDING,
            lockfile.content.match(LOCKFILE_ENDING)&.[](:ending) || "\n"
          )
        end

        def sanitized_gemspec_content(gemspec)
          gemspec_content = gemspec.content.gsub(/^\s*require.*$/, "")
          gemspec_content.gsub(/=.*VERSION.*$/) do
            parsed_lockfile ||= ::Bundler::LockfileParser.new(lockfile.content)
            gem_name = gemspec.name.split("/").last.split(".").first
            spec = parsed_lockfile.specs.find { |s| s.name == gem_name }
            "='#{spec&.version || '0.0.1'}'"
          end
        end

        class ReplaceRequirement < Parser::Rewriter
          SKIPPED_TYPES = %i(send lvar dstr).freeze

          def initialize(dependency:, filename:)
            @dependency = dependency
            @filename = filename

            return if filename == "Gemfile" || filename.end_with?(".gemspec")
            raise "File must be a Gemfile or gemspec"
          end

          def on_send(node)
            return unless declares_targeted_gem?(node)

            req_nodes = node.children[3..-1]
            req_nodes = req_nodes.reject { |child| child.type == :hash }

            return if req_nodes.none?
            return if req_nodes.any? { |n| SKIPPED_TYPES.include?(n.type) }

            quote_character = extract_quote_character_from(req_nodes)

            replace(
              range_for(req_nodes),
              new_requirement_string(quote_character)
            )
          end

          private

          attr_reader :dependency, :filename

          def declaration_methods
            return %i(gem) if filename == "Gemfile"
            %i(add_dependency add_runtime_dependency add_development_dependency)
          end

          def declares_targeted_gem?(node)
            return false unless declaration_methods.include?(node.children[1])
            node.children[2].children.first == dependency.name
          end

          def extract_quote_character_from(requirement_nodes)
            case requirement_nodes.first.type
            when :str, :dstr
              requirement_nodes.first.loc.begin.source
            else
              requirement_nodes.first.children.first.loc.begin.source
            end
          end

          def new_requirement_string(quote_character)
            dependency.requirements.
              find { |r| r[:file] == filename }.
              fetch(:requirement).split(",").
              map { |r| %(#{quote_character}#{r.strip}#{quote_character}) }.
              join(", ")
          end

          def range_for(nodes)
            nodes.first.loc.begin.begin.join(nodes.last.loc.expression)
          end
        end
      end
    end
  end
end
