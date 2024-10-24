# typed: true
# frozen_string_literal: true

require "open3"

module Dependabot
  module MavenOSV
    module Utils
      module OSVScanner
        extend T::Sig
        extend T::Helpers

        Package = Struct.new(:source_file, :name, :version)

        sig { params(pomfile_path: String).returns(T::Array[Package]) }
        def self.scan(pomfile_path:)
          JSON.parse(cached_osv_scan(pomfile_path:)).fetch("results").flat_map do |result|
            result.fetch("packages").map do |package|
              Package.new(
                source_file: result.dig("source", "path"),
                name: package.dig("package", "name"),
                version: package.dig("package", "version")
              )
            end
          end
        end

        sig { params(pomfile_path: String).void }
        def self.fix(pomfile_path:)
          return if File.exist?(osv_scanner_resolution_file_path(pomfile_path:))

          command_args = %W(fix
                            --non-interactive --maven-fix-management
                            --experimental-offline --data-source native
                            -M #{pomfile_path})
          run(args: command_args)

          # after applying a fix, remove any cached scan information
          # File.unlink(cached_osv_scan_location(pomfile_path:)) if File.exist?(cached_osv_scan_location(pomfile_path:))
        end

        sig { params(pomfile_path: String).returns(String) }
        def self.osv_scanner_resolution_file_path(pomfile_path:)
          File.join(File.dirname(pomfile_path), "pom.xml.resolve.maven")
        end

        sig { params(pomfile_path: String).returns(String) }
        def self.cached_osv_scan(pomfile_path:)
          cached_location = cached_osv_scan_location(pomfile_path:)
          return File.read(cached_location) if File.exist?(cached_location)

          command_args = %W(scan --experimental-offline --experimental-all-packages --format json
                            #{File.dirname(pomfile_path)})
          run(args: command_args).tap { |output| File.write(cached_location, output) }
        end

        sig { params(pomfile_path: String).returns(String) }
        def self.cached_osv_scan_location(pomfile_path:)
          File.join(File.dirname(pomfile_path), "osv_scan.json")
        end

        sig { params(args: T::Array[String]).returns(String) }
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
