# frozen_string_literal: true

require "toml-rb"

require "dependabot/shared_helpers"
require "dependabot/dependency_file"
require "dependabot/file_updaters/go/dep"
require "dependabot/file_parsers/go/dep"

module Dependabot
  module FileUpdaters
    module Cocoa
      class CocoaPods
        class LockfileUpdater
          def initialize(dependencies:, dependency_files:, credentials:)
            @dependencies = dependencies
            @dependency_files = dependency_files
            @credentials = credentials
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
