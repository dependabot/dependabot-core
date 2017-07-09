# frozen_string_literal: true
require "cocoapods"
require "gemnasium/parser"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/file_updaters/cocoa/cocoa_pods"

module Dependabot
  module UpdateCheckers
    module Cocoa
      class CocoaPods < Dependabot::UpdateCheckers::Base
        def latest_version
          @latest_version ||= fetch_latest_version
        end

        private

        def fetch_latest_version
          parsed_file = Pod::Podfile.from_ruby(nil, podfile.content)
          pod = parsed_file.dependencies.find { |d| d.name == dependency.name }

          return nil if pod.external_source

          specs = pod_analyzer.analyze.specifications

          Gem::Version.new(specs.find { |d| d.name == dependency.name }.version)
        end

        def pod_analyzer
          @pod_analyzer =
            begin
              lockfile_hash =
                Pod::YAMLHelper.load_string(lockfile_for_update_check)
              parsed_lockfile = Pod::Lockfile.new(lockfile_hash)

              evaluated_podfile =
                Pod::Podfile.from_ruby(nil, podfile_for_update_check)

              pod_sandbox = Pod::Sandbox.new("tmp")

              analyzer = Pod::Installer::Analyzer.new(
                pod_sandbox,
                evaluated_podfile,
                parsed_lockfile
              )

              analyzer.installation_options.integrate_targets = false
              analyzer.update = { pods: ["Alamofire"] }

              analyzer.config.silent = true
              analyzer.update_repositories

              analyzer
            end
        end

        def lockfile
          lockfile = dependency_files.find { |f| f.name == "Podfile.lock" }
          raise "No Podfile.lock!" unless lockfile
          lockfile
        end

        def podfile
          podfile = dependency_files.find { |f| f.name == "Podfile" }
          raise "No Podfile!" unless podfile
          podfile
        end

        def podfile_for_update_check
          content = remove_dependency_requirement(podfile.content)
          content = replace_ssh_links_with_https(content)
          prepend_git_auth_details(content)
        end

        def lockfile_for_update_check
          content = replace_ssh_links_with_https(lockfile.content)
          prepend_git_auth_details(content)
        end

        # Replace the original pod requirements with nothing, to fully "unlock"
        # the pod during version checking
        def remove_dependency_requirement(podfile_content)
          regex = Dependabot::FileUpdaters::Cocoa::CocoaPods::POD_CALL

          podfile_content.
            to_enum(:scan, regex).
            find { Regexp.last_match[:name] == dependency.name }

          original_pod_declaration_string = Regexp.last_match.to_s
          updated_pod_declaration_string =
            original_pod_declaration_string.
            sub(/,[ \t]*#{Gemnasium::Parser::Patterns::REQUIREMENTS}/, "")

          podfile_content.gsub(
            original_pod_declaration_string,
            updated_pod_declaration_string
          )
        end

        def replace_ssh_links_with_https(content)
          content.gsub("git@github.com:", "https://github.com/")
        end

        # TODO: replace this with a setting in CocoaPods, like we do for Bundler
        def prepend_git_auth_details(content)
          content.gsub(
            "https://github.com/",
            "https://x-access-token:#{github_access_token}@github.com/"
          )
        end
      end
    end
  end
end
