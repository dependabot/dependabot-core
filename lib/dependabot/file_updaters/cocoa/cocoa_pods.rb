# frozen_string_literal: true
require "cocoapods"
require "gemnasium/parser"
require "dependabot/file_updaters/base"
require "dependabot/file_fetchers/cocoa/cocoa_pods"

module Dependabot
  module FileUpdaters
    module Cocoa
      class CocoaPods < Dependabot::FileUpdaters::Base
        POD_CALL =
          /^[ \t]*pod\(?[ \t]*#{Gemnasium::Parser::Patterns::QUOTED_GEM_NAME}
           (?:[ \t]*,[ \t]*#{Gemnasium::Parser::Patterns::REQUIREMENT_LIST})?/x

        LOCKFILE_ENDING = /(?<ending>\s*PODFILE CHECKSUM.*)/m

        def updated_dependency_files
          [
            updated_file(file: podfile, content: updated_podfile_content),
            updated_file(file: lockfile, content: updated_lockfile_content)
          ]
        end

        private

        def required_files
          Dependabot::FileFetchers::Cocoa::CocoaPods.required_files
        end

        def podfile
          @podfile ||= get_original_file("Podfile")
        end

        def lockfile
          @lockfile ||= get_original_file("Podfile.lock")
        end

        def updated_podfile_content
          return @updated_podfile_content if @updated_podfile_content

          podfile.content.
            to_enum(:scan, POD_CALL).
            find { Regexp.last_match[:name] == dependency.name }

          original_pod_declaration_string = Regexp.last_match.to_s
          updated_pod_declaration_string =
            original_pod_declaration_string.
            sub(Gemnasium::Parser::Patterns::REQUIREMENTS) do |old_requirements|
              old_version =
                old_requirements.match(Gemnasium::Parser::Patterns::VERSION)[0]

              precision = old_version.split(".").count
              new_version =
                dependency.version.segments.first(precision).join(".")

              old_requirements.sub(old_version, new_version)
            end

          @updated_podfile_content = podfile.content.gsub(
            original_pod_declaration_string,
            updated_pod_declaration_string
          )
        end

        def updated_lockfile_content
          @updated_lockfile_content ||= build_updated_lockfile
        end

        def build_updated_lockfile
          external_source_pods =
            evaluated_podfile.dependencies.
            select(&:external_source).
            map(&:root_name).uniq

          checkout_options =
            pod_sandbox.checkout_sources.select do |root_name, _|
              external_source_pods.include?(root_name)
            end

          lockfile_content =
            Pod::Lockfile.generate(
              evaluated_podfile,
              pod_analyzer.analyze.specifications,
              checkout_options
            ).to_yaml

          post_process_lockfile(lockfile_content)
        end

        def pod_analyzer
          @pod_analyzer =
            begin
              lockfile_hash = Pod::YAMLHelper.load_string(lockfile.content)
              parsed_lockfile = Pod::Lockfile.new(lockfile_hash)

              analyzer = Pod::Installer::Analyzer.new(
                pod_sandbox,
                evaluated_podfile,
                parsed_lockfile
              )

              analyzer.installation_options.integrate_targets = false
              analyzer.update = { pods: [dependency.name] }

              analyzer.config.silent = true
              analyzer.update_repositories

              analyzer
            end
        end

        def pod_sandbox
          @sandbox ||= Pod::Sandbox.new("tmp")
        end

        def evaluated_podfile
          @evaluated_podfile ||=
            Pod::Podfile.from_ruby(nil, podfile_content_for_resolution)
        end

        # TODO: replace this with a setting in CocoaPods, like we do for Bundler
        def podfile_content_for_resolution
          # Prepend auth details to any git remotes
          updated_podfile_content.gsub(
            "git@github.com:",
            "https://#{github_access_token}:x-oauth-basic@github.com/"
          )
        end

        def post_process_lockfile(lockfile_body)
          # Remove any auth details we prepended to git remotes
          lockfile_body =
            lockfile_body.gsub(
              "https://#{github_access_token}:x-oauth-basic@github.com/",
              "git@github.com:"
            )

          # Add the correct Podfile checksum (i.e., without auth alterations)
          # and change the `COCOAPODS` version back to whatever it was before
          checksum =
            Digest::SHA1.hexdigest(updated_podfile_content).encode("UTF-8")
          old_cocoapods_line =
            lockfile.content.match(/COCOAPODS: \d\.\d\.\d.*/)[0]

          lockfile_body.gsub(
            /COCOAPODS: \d\.\d\.\d.*/,
            "PODFILE CHECKSUM: #{checksum}\n\n#{old_cocoapods_line}"
          )
        end
      end
    end
  end
end
