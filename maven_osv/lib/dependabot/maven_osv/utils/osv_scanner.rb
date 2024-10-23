# typed: true
# frozen_string_literal: true

require "open3"

module Dependabot
  module MavenOSV
    module Utils
      module OSVScanner
        def self.scan(pomfile_path:)
          JSON.parse(cached_osv_scan(pomfile_path:)).fetch("results").flat_map do |results|
            results.fetch("packages").map do |package|
              Dependency.new(
                name: package.dig("package", "name"),
                package_manager: "maven_osv",
                version: package.dig("package", "version"),
                directory: File.dirname(pomfile_path),
                requirements: [{
                  requirement: package.dig("package", "version"),
                  file: File.basename(pomfile_path),
                  source: nil,
                  groups: []
                }]
              )
            end
          end
        end

        def self.fix(pomfile_path:)
          command_args = %W(fix
                            --non-interactive --maven-fix-management
                            --experimental-offline --data-source native
                            -M #{pomfile_path})
          run(args: command_args)

          # after applying a fix, remove any cached scan information
          File.unlink(cached_osv_scan_location(pomfile_path:))
        end

        def self.cached_osv_scan(pomfile_path:)
          cached_location = cached_osv_scan_location(pomfile_path:)
          return File.read(cached_location) if File.exist?(cached_location)

          command_args = %W(scan --experimental-offline --experimental-all-packages --format json
                            #{File.dirname(pomfile_path)})
          run(args: command_args).tap { |output| File.write(cached_location, output) }
        end

        def self.cached_osv_scan_location(pomfile_path:)
          File.join(File.dirname(pomfile_path), "osv_scan.json")
        end

        def self.run(args: [])
          start = Time.now

          command = SharedHelpers.escape_command("osv-scanner #{args.join(' ')}")

          # Pass through any OSV_ environment variables
          env = ENV.select { |key, _value| key.match(/^OSV_/) }

          stdout, stderr, process = Open3.capture3(env, command)
          time_taken = Time.now - start

          # Raise an error with the output from the shell session if osv-scanner
          # returns a status > 1
          return stdout if T.must(process.exitstatus) <= 1

          raise SharedHelpers::HelperSubprocessFailed.new(
            message: stderr,
            error_context: {
              command: command,
              time_taken: time_taken,
              process_exit_value: process.to_s
            }
          )
        end
      end
    end
  end
end
