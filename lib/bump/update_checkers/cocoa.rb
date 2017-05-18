# frozen_string_literal: true
require "cocoapods"
require "gemnasium/parser"
require "bump/update_checkers/base"
require "bump/shared_helpers"
require "bump/errors"
require "bump/dependency_file_updaters/cocoa"

module Bump
  module UpdateCheckers
    class Cocoa < Base
      def latest_version
        @latest_version ||= fetch_latest_version
      end

      private

      def fetch_latest_version
        parsed_podfile = Pod::Podfile.from_ruby(nil, podfile.content)
        pod = parsed_podfile.dependencies.find { |d| d.name == dependency.name }

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
        podfile_content = podfile.content
        podfile_content = remove_dependency_requirement(podfile_content)
        prepend_git_auth_details(podfile_content)
      end

      def lockfile_for_update_check
        lockfile_content = lockfile.content
        prepend_git_auth_details(lockfile_content)
      end

      # Replace the original pod requirements with nothing, to fully "unlock"
      # the pod during version checking
      def remove_dependency_requirement(podfile_content)
        podfile_content.
          to_enum(:scan, Bump::DependencyFileUpdaters::Cocoa::POD_CALL).
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

      def prepend_git_auth_details(podfile_content)
        podfile_content.gsub(
          "git@github.com:",
          "https://#{github_access_token}:x-oauth-basic@github.com/"
        )
      end
    end
  end
end
