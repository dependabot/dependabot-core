# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module Go
      class Dep < Dependabot::FileUpdaters::Base
        def self.updated_files_regex
          [
            /^Gopkg\.toml$/,
            /^Gopkg\.lock$/
          ]
        end

        def updated_dependency_files
          updated_files = []

          if file_changed?(manifest)
            updated_files <<
              updated_file(
                file: manifest,
                content: updated_manifest_content
              )
          end

          if lockfile
            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)
          end

          raise "No files changed!" if updated_files.none?

          updated_files
        end

        private

        def check_required_files
          raise "No Gopkg.toml!" unless get_original_file("Gopkg.toml")
        end

        def manifest
          @manifest ||= get_original_file("Gopkg.toml")
        end

        def lockfile
          @lockfile ||= get_original_file("Gopkg.lock")
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

              raise "Expected content to change!" if content == updated_content
              updated_content
            end
        end

        def updated_lockfile_content
          # TODO: This normally needs to be written in the native language.
          # We do so by shelling out to a helper method (see other languages)
          lockfile.content
        end

        def update_requirements(content:, filename:, dependency:)
          updated_content = content.dup

          # The UpdateChecker ensures the order of requirements is preserved
          # when updating, so we can zip them together in new/old pairs.
          reqs = dependency.requirements.zip(dependency.previous_requirements).
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

        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        def update_manifest_req(content:, dep:, old_req:, new_req:)
          declaration = content.scan(declaration_regex(dep)).
                        find { |m| old_req.nil? || m.include?(old_req) }

          return content unless declaration

          if old_req && new_req
            content.gsub(declaration) do |line|
              line.gsub(old_req, new_req)
            end
          elsif old_req && new_req.nil?
            content.gsub(declaration) do |line|
              line.gsub(/\R+.*version\s*=.*/, "")
            end
          elsif old_req.nil? && new_req
            content.gsub(declaration) do |line|
              indent = line.match(/(?<indent>\s*)name/).named_captures["indent"]
              version_declaration = indent + "version = \"#{new_req}\""
              line.gsub(/name\s*=.*/) { |nm_ln| nm_ln + version_declaration }
            end
          end
        end
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity

        def update_manifest_pin(content:, dep:, old_pin:, new_pin:)
          declaration = content.scan(declaration_regex(dep)).
                        find { |m| m.include?(old_pin) }

          return content unless declaration

          if old_pin && new_pin
            content.gsub(declaration) do |line|
              line.gsub(old_pin, new_pin)
            end
          elsif old_pin && new_pin.nil?
            content.gsub(declaration) do |line|
              line.gsub(/\R+.*revision\s*=.*/, "").gsub(/\R+.*branch\s*=.*/, "")
            end
          end
        end

        def declaration_regex(dep)
          /
            (?<=\]\])
            (?:(?!^\[).)*
            name\s*=\s*["']#{Regexp.escape(dep.name)}["']
            (?:(?!^\[).)*
          /mx
        end
      end
    end
  end
end
