# frozen_string_literal: true

require "dependabot/file_updaters/rust/cargo"

module Dependabot
  module FileUpdaters
    module Rust
      class Cargo
        class ManifestUpdater
          def initialize(dependencies:, manifest:)
            @dependencies = dependencies
            @manifest = manifest
          end

          def updated_manifest_content
            dependencies.
              select { |dep| requirement_changed?(manifest, dep) }.
              reduce(manifest.content.dup) do |content, dep|
                updated_content = content

                updated_content = update_requirements(
                  content: updated_content,
                  filename: manifest.name,
                  dependency: dep
                )

                updated_content = update_git_pin(
                  content: updated_content,
                  filename: manifest.name,
                  dependency: dep
                )

                if content == updated_content
                  raise "Expected content to change!"
                end

                updated_content
              end
          end

          private

          attr_reader :dependencies, :manifest

          def requirement_changed?(file, dependency)
            changed_requirements =
              dependency.requirements - dependency.previous_requirements

            changed_requirements.any? { |f| f[:file] == file.name }
          end

          def update_requirements(content:, filename:, dependency:)
            updated_content = content.dup

            # The UpdateChecker ensures the order of requirements is preserved
            # when updating, so we can zip them together in new/old pairs.
            reqs = dependency.requirements.
                   zip(dependency.previous_requirements).
                   reject { |new_req, old_req| new_req == old_req }

            # Loop through each changed requirement
            reqs.each do |new_req, old_req|
              raise "Bad req match" unless new_req[:file] == old_req[:file]
              next if new_req[:requirement] == old_req[:requirement]
              next unless new_req[:file] == filename

              updated_content = update_manifest_req(
                content: updated_content,
                dep: dependency,
                old_req: old_req.fetch(:requirement),
                new_req: new_req.fetch(:requirement)
              )
            end

            updated_content
          end

          def update_git_pin(content:, filename:, dependency:)
            updated_pin =
              dependency.requirements.
              find { |r| r[:file] == filename }&.
              dig(:source, :ref)

            old_pin =
              dependency.previous_requirements.
              find { |r| r[:file] == filename }&.
              dig(:source, :ref)

            return content unless old_pin

            update_manifest_pin(
              content: content,
              dep: dependency,
              old_pin: old_pin,
              new_pin: updated_pin
            )
          end

          def update_manifest_req(content:, dep:, old_req:, new_req:)
            simple_declaration = content.scan(declaration_regex(dep)).
                                 find { |m| m.include?(old_req) }

            if simple_declaration
              content.gsub(simple_declaration) do |line|
                line.gsub(old_req, new_req)
              end
            elsif content.match?(feature_declaration_version_regex(dep))
              content.gsub(feature_declaration_version_regex(dep)) do |part|
                line = content.match(feature_declaration_version_regex(dep)).
                       named_captures.fetch("version_declaration")
                new_line = line.gsub(old_req, new_req)
                part.gsub(line, new_line)
              end
            else
              content
            end
          end

          def update_manifest_pin(content:, dep:, old_pin:, new_pin:)
            simple_declaration = content.scan(declaration_regex(dep)).
                                 find { |m| m.include?(old_pin) }

            if simple_declaration
              content.gsub(simple_declaration) do |line|
                line.gsub(old_pin, new_pin)
              end
            elsif content.match?(feature_declaration_pin_regex(dep))
              content.gsub(feature_declaration_pin_regex(dep)) do |part|
                line = content.match(feature_declaration_pin_regex(dep)).
                       named_captures.fetch("pin_declaration")
                new_line = line.gsub(old_pin, new_pin)
                part.gsub(line, new_line)
              end
            else
              content
            end
          end

          def declaration_regex(dep)
            /(?:^|["'])#{Regexp.escape(dep.name)}["']?\s*=.*$/i
          end

          def feature_declaration_version_regex(dep)
            /
              #{Regexp.quote("dependencies.#{dep.name}]")}
              (?:(?!^\[).)+
              (?<version_declaration>version\s*=.*)$
            /mx
          end

          def feature_declaration_pin_regex(dep)
            /
              #{Regexp.quote("dependencies.#{dep.name}]")}
              (?:(?!^\[).)+
              (?<pin_declaration>(?:tag|rev)\s*=.*)$
            /mx
          end
        end
      end
    end
  end
end
