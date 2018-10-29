# frozen_string_literal: true

require "toml-rb"

require "dependabot/shared_helpers"
require "dependabot/dependency_file"
require "dependabot/file_updaters/cocoa/cocoapods.rb"
require "dependabot/update_checkers/cocoa/cocoapods.rb"

module Dependabot
  module FileUpdaters
    module Cocoa
      class CocoaPods
        class LockfileUpdater
          def initialize(dependencies:, podfile:, lockfile:, credentials:)
            @dependencies = dependencies
            @podfile = podfile
            @lockfile = lockfile
            @credentials = credentials
          end

          def updated_lockfile_content
            external_source_pods =
              evaluated_podfile.dependencies.
              select(&:external_source).
              map(&:root_name).uniq

            lockfile_hash =
                Pod::YAMLHelper.load_string(@lockfile.content)
            parsed_lockfile = Pod::Lockfile.new(lockfile_hash)
            pod_sandbox = Pod::Sandbox.new("tmp")
            analyzer = Pod::Installer::Analyzer.new(
              pod_sandbox,
              evaluated_podfile,
              parsed_lockfile
            )

            checkout_options =
              pod_sandbox.checkout_sources.select do |root_name, _|
                external_source_pods.include?(root_name)
              end

            lockfile_content =
              Pod::Lockfile.generate(
                evaluated_podfile,
                analyzer.analyze.specifications,
                checkout_options
              ).to_yaml

            post_process_lockfile(lockfile_content)
          end

          def evaluated_podfile
            @evaluated_podfile ||=
              Pod::Podfile.from_ruby(nil, @podfile)
          end

          def post_process_lockfile(lockfile_body)
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
end
