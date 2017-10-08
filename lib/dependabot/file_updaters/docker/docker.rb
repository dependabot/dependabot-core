# frozen_string_literal: true

require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module Docker
      class Docker < Dependabot::FileUpdaters::Base
        def self.updated_files_regex
          [/^Dockerfile$/]
        end

        def updated_dependency_files
          [updated_file(file: dockerfile, content: updated_dockerfile_content)]
        end

        private

        def check_required_files
          %w(Dockerfile).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def updated_dockerfile_content
          from_regex = /[Ff][Rr][Oo][Mm]/
          old_declaration = "#{dependency.name}:#{dependency.previous_version}"
          escaped_declaration = Regexp.escape(old_declaration)

          old_declaration_regex = /^#{from_regex}\s+#{escaped_declaration}/

          dockerfile.content.gsub(old_declaration_regex) do |old_dec|
            old_dec.gsub(
              ":#{dependency.previous_version}",
              ":#{dependency.version}"
            )
          end
        end

        def dockerfile
          @dockerfile ||= dependency_files.find { |f| f.name == "Dockerfile" }
        end
      end
    end
  end
end
