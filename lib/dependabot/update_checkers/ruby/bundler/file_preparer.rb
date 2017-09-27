# frozen_string_literal: true

require "dependabot/update_checkers/ruby/bundler"
require "dependabot/file_updaters/ruby/bundler"
require "dependabot/dependency_file"
require "parser/current"

module Dependabot
  module UpdateCheckers
    module Ruby
      class Bundler
        # This class takes a set of dependency files and sanitizes them for use
        # in UpdateCheckers::Ruby::Bundler. In particular, it:
        # - Removes any version requirement on the dependency being updated
        #   (in the Gemfile)
        # - Sanitizes any provided gemspecs to remove file imports etc. (since
        #   Dependabot doesn't pull down the entire repo). This process is
        #   imperfect - an alternative would be to cloen the repo
        class FilePreparer
          def initialize(dependency_files:, dependency:)
            @dependency_files = dependency_files
            @dependency = dependency
          end

          def prepared_dependency_files
            files = []

            if gemfile
              files << DependencyFile.new(
                name: gemfile.name,
                content: gemfile_content_for_update_check,
                directory: gemfile.directory
              )
            end

            if gemspec
              files << DependencyFile.new(
                name: gemspec.name,
                content: gemspec_content_for_update_check,
                directory: gemspec.directory
              )
            end

            path_gemspecs.compact.each do |file|
              files << DependencyFile.new(
                name: file.name,
                content: sanitized_gemspec_content(file.content),
                directory: file.directory
              )
            end

            # No editing required for lockfile or Ruby version file
            files += [lockfile, ruby_version_file].compact
          end

          private

          attr_reader :dependency_files, :dependency

          def gemfile
            dependency_files.find { |f| f.name == "Gemfile" }
          end

          def lockfile
            dependency_files.find { |f| f.name == "Gemfile.lock" }
          end

          def gemspec
            dependency_files.find { |f| f.name.match?(%r{^[^/]*\.gemspec$}) }
          end

          def ruby_version_file
            dependency_files.find { |f| f.name == ".ruby-version" }
          end

          def path_gemspecs
            all = dependency_files.select { |f| f.name.end_with?(".gemspec") }
            all - [gemspec]
          end

          def gemfile_content_for_update_check
            content = replace_gemfile_version_requirement(gemfile.content)
            content
          end

          def gemspec_content_for_update_check
            content =
              if original_gemspec_declaration_string
                gemspec.content.gsub(
                  original_gemspec_declaration_string,
                  updated_gemspec_declaration_string
                )
              else
                gemspec.content
              end

            sanitized_gemspec_content(content)
          end

          def original_gemspec_declaration_string
            matches = []
            regex = FileUpdaters::Ruby::Bundler::DEPENDENCY_DECLARATION_REGEX

            @original_gemspec_declaration_string ||=
              begin
                gemspec.content.scan(regex) { matches << Regexp.last_match }
                matches.find { |match| match[:name] == dependency.name }&.to_s
              end
          end

          def updated_gemspec_declaration_string
            regex = FileUpdaters::Ruby::Bundler::DEPENDENCY_DECLARATION_REGEX
            original_requirement =
              regex.match(original_gemspec_declaration_string)[:requirements]

            original_gemspec_declaration_string.
              sub(original_requirement, '">= 0"')
          end

          def sanitized_gemspec_content(gemspec_content)
            # No need to set the version correctly - this is just an update
            # check so we're not going to persist any changes to the lockfile.
            gemspec_content.
              gsub(/^\s*require.*$/, "").
              gsub(/=.*VERSION.*$/, "= '0.0.1'")
          end

          def replace_gemfile_version_requirement(content)
            buffer = ::Parser::Source::Buffer.new("(gemfile_content)")
            buffer.source = content
            ast = Parser::CurrentRuby.new.parse(buffer)

            updated_version =
              if dependency.version&.match?(/^[0-9a-f]{40}$/) then 0
              elsif dependency.version then dependency.version
              else 0
              end

            ReplaceGemfileVersion.new(
              dependency_name: dependency.name,
              updated_version: updated_version
            ).rewrite(buffer, ast)
          end

          class ReplaceGemfileVersion < Parser::Rewriter
            def initialize(dependency_name:, updated_version:)
              @dependency_name = dependency_name
              @updated_version = updated_version
            end

            def on_send(node)
              return unless declares_targeted_gem?(node)

              version_requirement_nodes =
                node.children[3..-1].reject { |child| child.type == :hash }

              return if version_requirement_nodes.none?

              version_requirement_nodes.each do |requirement_node|
                replace(
                  requirement_node.loc.expression,
                  "'>= #{updated_version}'"
                )
              end
            end

            private

            attr_reader :dependency_name, :updated_version

            def declares_targeted_gem?(node)
              return false unless node.children[1] == :gem
              node.children[2].children.first == dependency_name
            end
          end
        end
      end
    end
  end
end
