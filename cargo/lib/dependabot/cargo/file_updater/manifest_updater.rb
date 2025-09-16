# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/cargo/file_updater"

module Dependabot
  module Cargo
    class FileUpdater
      class ManifestUpdater
        extend T::Sig

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            manifest: Dependabot::DependencyFile
          ).void
        end
        def initialize(dependencies:, manifest:)
          @dependencies = T.let(dependencies, T::Array[Dependabot::Dependency])
          @manifest = T.let(manifest, Dependabot::DependencyFile)
        end

        sig { returns(String) }
        def updated_manifest_content
          content = manifest.content
          raise "Manifest has no content" if content.nil?

          dependencies
            .select { |dep| requirement_changed?(manifest, dep) }
            .reduce(content.dup) do |current_content, dep|
              updated_content = current_content

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

              raise "Expected content to change!" if current_content == updated_content

              updated_content
            end
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :manifest

        sig { params(file: Dependabot::DependencyFile, dependency: Dependabot::Dependency).returns(T::Boolean) }
        def requirement_changed?(file, dependency)
          changed_requirements =
            dependency.requirements - (dependency.previous_requirements || [])

          changed_requirements.any? { |f| f[:file] == file.name }
        end

        sig { params(content: String, filename: String, dependency: Dependabot::Dependency).returns(String) }
        def update_requirements(content:, filename:, dependency:)
          updated_content = T.let(content.dup, String)

          # The UpdateChecker ensures the order of requirements is preserved
          # when updating, so we can zip them together in new/old pairs.
          reqs = dependency.requirements
                           .zip(dependency.previous_requirements || [])
                           .reject { |new_req, old_req| new_req == old_req }

          # Loop through each changed requirement
          reqs.each do |new_req, old_req|
            next if old_req.nil?

            raise "Bad req match" unless new_req[:file] == old_req[:file]
            next if new_req[:requirement] == old_req[:requirement]
            next unless new_req[:file] == filename

            updated_content =
              update_manifest_req(
                content: updated_content,
                dep: dependency,
                old_req: old_req.fetch(:requirement),
                new_req: new_req.fetch(:requirement)
              )
          end

          updated_content
        end

        sig { params(content: String, filename: String, dependency: Dependabot::Dependency).returns(String) }
        def update_git_pin(content:, filename:, dependency:)
          updated_pin =
            dependency.requirements
                      .find { |r| r[:file] == filename }
                      &.dig(:source, :ref)

          old_pin =
            dependency.previous_requirements
                      &.find { |r| r[:file] == filename }
                      &.dig(:source, :ref)

          return content unless old_pin

          update_manifest_pin(
            content: content,
            dep: dependency,
            old_pin: old_pin,
            new_pin: updated_pin
          )
        end

        sig do
          params(
            content: String,
            dep: Dependabot::Dependency,
            old_req: String,
            new_req: String
          ).returns(String)
        end
        def update_manifest_req(content:, dep:, old_req:, new_req:)
          simple_declaration = content.scan(declaration_regex(dep))
                                      .find { |m| m.include?(old_req) }

          if simple_declaration
            simple_declaration_regex =
              /(?:^|["'])#{Regexp.escape(T.cast(simple_declaration, String))}/
            old_req_escaped = Regexp.escape(old_req)
            content.gsub(simple_declaration_regex) do |line|
              line.gsub(/.+=.*\K(#{old_req_escaped})/, new_req)
            end
          elsif content.match?(feature_declaration_version_regex(dep))
            content.gsub(feature_declaration_version_regex(dep)) do |part|
              match_data = content.match(feature_declaration_version_regex(dep))
              line = T.must(match_data).named_captures.fetch("version_declaration")
              return content if line.nil?

              new_line = line.gsub(old_req, new_req)
              part.gsub(line, new_line)
            end
          else
            content
          end
        end

        sig do
          params(
            content: String,
            dep: Dependabot::Dependency,
            old_pin: String,
            new_pin: String
          )
            .returns(String)
        end
        def update_manifest_pin(content:, dep:, old_pin:, new_pin:)
          simple_declaration = content.scan(declaration_regex(dep))
                                      .find { |m| m.include?(old_pin) }

          if simple_declaration
            simple_declaration_regex =
              /(?:^|["'])#{Regexp.escape(T.cast(simple_declaration, String))}/
            content.gsub(simple_declaration_regex) do |line|
              line.gsub(old_pin, new_pin)
            end
          elsif content.match?(feature_declaration_pin_regex(dep))
            content.gsub(feature_declaration_pin_regex(dep)) do |part|
              match_data = content.match(feature_declaration_pin_regex(dep))
              line = T.must(match_data).named_captures.fetch("pin_declaration")
              return content if line.nil?

              new_line = line.gsub(old_pin, new_pin)
              part.gsub(line, new_line)
            end
          else
            content
          end
        end

        sig { params(dep: Dependabot::Dependency).returns(Regexp) }
        def declaration_regex(dep)
          /(?:^|^\s*|["'])#{Regexp.escape(dep.name)}["']?(?:\s*\.version)?\s*=.*$/i
        end

        sig { params(dep: Dependabot::Dependency).returns(Regexp) }
        def feature_declaration_version_regex(dep)
          /
            #{Regexp.quote("dependencies.#{dep.name}]")}
            (?:(?!^\[).)+
            (?<version_declaration>version\s*=[^\[]*)$
          /mx
        end

        sig { params(dep: Dependabot::Dependency).returns(Regexp) }
        def feature_declaration_pin_regex(dep)
          /
            #{Regexp.quote("dependencies.#{dep.name}]")}
            (?:(?!^\[).)+
            (?<pin_declaration>(?:tag|rev)\s*=[^\[]*)$
          /mx
        end
      end
    end
  end
end
