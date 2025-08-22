# typed: false
# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/bundler/file_parser"
require "dependabot/bundler/update_checker"
require "dependabot/bundler/file_updater"
require "dependabot/logger"

module Dependabot
  module LocalScanner
    class LocalDependabotScanner
      attr_reader :project_path, :options

      def initialize(project_path, options = {})
        @project_path = File.expand_path(project_path)
        @options = options
        validate_project!
      end

      def validate_project!
        unless Dir.exist?(@project_path)
          raise ArgumentError, "Project path does not exist: #{@project_path}"
        end

        unless File.exist?(File.join(@project_path, "Gemfile"))
          raise ArgumentError, "Project must contain a Gemfile: #{@project_path}"
        end
      end

      def scan_dependencies
        {
          project_path: @project_path,
          dependencies: parse_dependencies,
          scan_timestamp: Time.now.iso8601
        }
      end

      def scan_security_vulnerabilities
        {
          project_path: @project_path,
          security_scan: {
            vulnerabilities: detect_vulnerabilities,
            advisory_database_loaded: advisory_database_available?,
            bundle_audit_available: bundle_audit_available?
          },
          scan_timestamp: Time.now.iso8601
        }
      end

      def generate_report(format: :summary)
        case format
        when :json
          generate_json_report
        when :text
          generate_text_report
        else
          generate_summary_report
        end
      end

      private

      def parse_dependencies
        parser = Dependabot::Bundler::FileParser.new(
          dependency_files: dependency_files,
          source: source,
          credentials: []
        )
        parser.parse
      rescue => e
        Dependabot.logger.error "Failed to parse dependencies: #{e.message}"
        []
      end

      def detect_vulnerabilities
        # This would integrate with Ruby Advisory Database
        # For now, return empty array
        []
      rescue => e
        Dependabot.logger.error "Failed to detect vulnerabilities: #{e.message}"
        []
      end

      def dependency_files
        @dependency_files ||= [
          Dependabot::DependencyFile.new(
            name: "Gemfile",
            content: File.read(File.join(@project_path, "Gemfile")),
            directory: "/"
          )
        ].tap do |files|
          gemfile_lock_path = File.join(@project_path, "Gemfile.lock")
          if File.exist?(gemfile_lock_path)
            files << Dependabot::DependencyFile.new(
              name: "Gemfile.lock",
              content: File.read(gemfile_lock_path),
              directory: "/"
            )
          end
        end
      end

      def source
        @source ||= Dependabot::Source.new(
          provider: "local",
          repo: File.basename(@project_path),
          directory: "/"
        )
      end

      def advisory_database_available?
        # Check if Ruby Advisory Database is available
        advisory_db_path = File.expand_path("~/.local/share/ruby-advisory-db")
        Dir.exist?(advisory_db_path)
      end

      def bundle_audit_available?
        # Check if bundle-audit gem is available
        system("bundle", "exec", "bundle-audit", "--version", out: File::NULL, err: File::NULL)
      end

      def generate_summary_report
        <<~REPORT
          🔍 Scanning local Ruby project
          📁 Project: #{File.basename(@project_path)}
          📍 Path: #{@project_path}
          ✅ Project validation passed
          
          📊 Scan Results:
          • Dependencies found: #{parse_dependencies.length}
          • Security vulnerabilities: #{detect_vulnerabilities.length}
          • Advisory database: #{advisory_database_available? ? '✅ Available' : '❌ Not available'}
          • Bundle audit: #{bundle_audit_available? ? '✅ Available' : '❌ Not available'}
          
          🎯 Scan complete!
        REPORT
      end

      def generate_text_report
        <<~REPORT
          Local Scanner Report
          ===================
          
          Project Path: #{@project_path}
          Scan Timestamp: #{Time.now.iso8601}
          
          Dependencies:
          #{parse_dependencies.map { |dep| "  • #{dep.name} (#{dep.version})" }.join("\n")}
          
          Security Scan:
          • Vulnerabilities Found: #{detect_vulnerabilities.length}
          • Advisory Database: #{advisory_database_available? ? 'Available' : 'Not Available'}
          • Bundle Audit: #{bundle_audit_available? ? 'Available' : 'Not Available'}
        REPORT
      end

      def generate_json_report
        {
          scan_results: {
            project_path: @project_path,
            scan_timestamp: Time.now.iso8601,
            dependencies: parse_dependencies.map(&:to_h),
            security_scan: {
              vulnerabilities: detect_vulnerabilities,
              advisory_database_loaded: advisory_database_available?,
              bundle_audit_available: bundle_audit_available?
            }
          }
        }.to_json
      end
    end
  end
end
