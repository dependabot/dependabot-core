# frozen_string_literal: true

require "toml-rb"
require "dependabot/dependency_file"
require "dependabot/cargo/file_parser"
require "dependabot/cargo/update_checker"

module Dependabot
  module Cargo
    class UpdateChecker
      # This class takes a set of dependency files and sanitizes them for use
      # in UpdateCheckers::Rust::Cargo.
      class FilePreparer
        def initialize(dependency_files:, dependency:,
                       unlock_requirement: true,
                       replacement_git_pin: nil,
                       latest_allowable_version: nil)
          @dependency_files         = dependency_files
          @dependency               = dependency
          @unlock_requirement       = unlock_requirement
          @replacement_git_pin      = replacement_git_pin
          @latest_allowable_version = latest_allowable_version
        end

        def prepared_dependency_files
          files = []
          files += manifest_files.map do |file|
            DependencyFile.new(
              name: file.name,
              content: manifest_content_for_update_check(file),
              directory: file.directory
            )
          end
          files << lockfile if lockfile
          files << toolchain if toolchain
          files
        end

        private

        attr_reader :dependency_files, :dependency, :replacement_git_pin,
                    :latest_allowable_version

        def unlock_requirement?
          @unlock_requirement
        end

        def replace_git_pin?
          !replacement_git_pin.nil?
        end

        def manifest_content_for_update_check(file)
          content = file.content

          unless file.support_file?
            content = replace_version_constraint(content, file.name)
            content = replace_git_pin(content) if replace_git_pin?
          end

          content = replace_ssh_urls(content)

          content
        end

        # NOTE: We don't need to care about formatting in this method, since
        # we're only using the manifest to find the latest resolvable version
        def replace_version_constraint(content, filename)
          parsed_manifest = TomlRB.parse(content)

          Cargo::FileParser::DEPENDENCY_TYPES.each do |type|
            dependency_names_for_type(parsed_manifest, type).each do |name|
              req = parsed_manifest.dig(type, name)

              updated_req = temporary_requirement_for_resolution(filename)

              if req.is_a?(Hash)
                parsed_manifest[type][name]["version"] = updated_req
              else
                parsed_manifest[type][name] = updated_req
              end
            end
          end

          replace_req_on_target_specific_deps!(parsed_manifest, filename)

          TomlRB.dump(parsed_manifest)
        end

        def replace_req_on_target_specific_deps!(parsed_manifest, filename)
          parsed_manifest.fetch("target", {}).each do |target, _|
            Cargo::FileParser::DEPENDENCY_TYPES.each do |type|
              dependency_names = dependency_names_for_type_and_target(
                parsed_manifest,
                type,
                target
              )

              dependency_names.each do |name|
                req = parsed_manifest.dig("target", target, type, name)

                updated_req = temporary_requirement_for_resolution(filename)

                if req.is_a?(Hash)
                  parsed_manifest["target"][target][type][name]["version"] =
                    updated_req
                else
                  parsed_manifest["target"][target][type][name] = updated_req
                end
              end
            end
          end
        end

        def replace_git_pin(content)
          parsed_manifest = TomlRB.parse(content)

          Cargo::FileParser::DEPENDENCY_TYPES.each do |type|
            dependency_names_for_type(parsed_manifest, type).each do |name|
              req = parsed_manifest.dig(type, name)
              next unless req.is_a?(Hash)
              next unless [req["tag"], req["rev"]].compact.uniq.count == 1

              parsed_manifest[type][name]["tag"] = replacement_git_pin if req["tag"]

              parsed_manifest[type][name]["rev"] = replacement_git_pin if req["rev"]
            end
          end

          replace_git_pin_on_target_specific_deps!(parsed_manifest)

          TomlRB.dump(parsed_manifest)
        end

        def replace_git_pin_on_target_specific_deps!(parsed_manifest)
          parsed_manifest.fetch("target", {}).each do |target, _|
            Cargo::FileParser::DEPENDENCY_TYPES.each do |type|
              dependency_names = dependency_names_for_type_and_target(
                parsed_manifest,
                type,
                target
              )

              dependency_names.each do |name|
                req = parsed_manifest.dig("target", target, type, name)
                next unless req.is_a?(Hash)
                next unless [req["tag"], req["rev"]].compact.uniq.count == 1

                if req["tag"]
                  parsed_manifest["target"][target][type][name]["tag"] =
                    replacement_git_pin
                end

                if req["rev"]
                  parsed_manifest["target"][target][type][name]["rev"] =
                    replacement_git_pin
                end
              end
            end
          end
        end

        def replace_ssh_urls(content)
          parsed_manifest = TomlRB.parse(content)

          Cargo::FileParser::DEPENDENCY_TYPES.each do |type|
            (parsed_manifest[type] || {}).each do |_, details|
              next unless details.is_a?(Hash)
              next unless details["git"]

              details["git"] = details["git"].
                               gsub(%r{ssh://git@(.*?)/}, 'https://\1/')
            end
          end

          TomlRB.dump(parsed_manifest)
        end

        def temporary_requirement_for_resolution(filename)
          original_req = dependency.requirements.
                         find { |r| r.fetch(:file) == filename }&.
                         fetch(:requirement)

          lower_bound_req =
            if original_req && !unlock_requirement?
              original_req
            else
              ">= #{lower_bound_version}"
            end

          unless latest_allowable_version &&
                 Cargo::Version.correct?(latest_allowable_version) &&
                 Cargo::Version.new(latest_allowable_version) >=
                 Cargo::Version.new(lower_bound_version)
            return lower_bound_req
          end

          lower_bound_req + ", <= #{latest_allowable_version}"
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def lower_bound_version
          @lower_bound_version ||=
            if git_dependency? && git_dependency_version
              git_dependency_version
            elsif !git_dependency? && dependency.version
              dependency.version
            else
              version_from_requirement =
                dependency.requirements.filter_map { |r| r.fetch(:requirement) }.
                flat_map { |req_str| Cargo::Requirement.new(req_str) }.
                flat_map(&:requirements).
                reject { |req_array| req_array.first.start_with?("<") }.
                map(&:last).
                max&.to_s

              version_from_requirement || 0
            end
        end
        # rubocop:enable Metrics/PerceivedComplexity

        def git_dependency_version
          return unless lockfile

          TomlRB.parse(lockfile.content).
            fetch("package", []).
            select { |p| p["name"] == dependency.name }.
            find { |p| p["source"].end_with?(dependency.version) }.
            fetch("version")
        end

        def dependency_names_for_type(parsed_manifest, type)
          names = []
          parsed_manifest.fetch(type, {}).each do |nm, req|
            next unless dependency.name == name_from_declaration(nm, req)

            names << nm
          end
          names
        end

        def dependency_names_for_type_and_target(parsed_manifest, type, target)
          names = []
          (parsed_manifest.dig("target", target, type) || {}).each do |nm, req|
            next unless dependency.name == name_from_declaration(nm, req)

            names << nm
          end
          names
        end

        def name_from_declaration(name, declaration)
          return name if declaration.is_a?(String)
          raise "Unexpected dependency declaration: #{declaration}" unless declaration.is_a?(Hash)

          declaration.fetch("package", name)
        end

        def manifest_files
          @manifest_files ||=
            dependency_files.select { |f| f.name.end_with?("Cargo.toml") }

          raise "No Cargo.toml!" if @manifest_files.none?

          @manifest_files
        end

        def lockfile
          @lockfile ||= dependency_files.find { |f| f.name == "Cargo.lock" }
        end

        def toolchain
          @toolchain ||=
            dependency_files.find { |f| f.name == "rust-toolchain" }
        end

        def git_dependency?
          GitCommitChecker.
            new(dependency: dependency, credentials: []).
            git_dependency?
        end
      end
    end
  end
end
