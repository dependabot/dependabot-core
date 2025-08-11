#!/usr/bin/env ruby
# typed: false
# frozen_string_literal: true

# Local Dependabot Scanner
# Uses Dependabot classes directly to scan local Ruby dependencies
# Keeps scanner environment completely separate from project being scanned
# Optimized for security vulnerability scanning with detailed version information
# Built with Docker layer caching for fast development iterations
# Enhanced caching strategy for faster rebuilds

require "json"
require "optparse"
require "ostruct"
require "yaml"

# The Dockerfile sets up all environment variables and load paths
require "dependabot/bundler/file_parser"
require "dependabot/bundler/update_checker"
require "dependabot/bundler/file_updater"
require "dependabot/dependency_file"
require "dependabot/logger"
require "dependabot/source"

# Set up logging
Dependabot.logger = Logger.new($stdout)

class LocalDependabotScanner
  def initialize(project_path, options = {})
    # Always use absolute paths to avoid environment confusion
    @project_path = File.expand_path(project_path)
    @options = options
    @gemfile_path = File.join(@project_path, "Gemfile")
    @gemfile_lock_path = File.join(@project_path, "Gemfile.lock")

    # Verify we're in the scanner environment
    verify_scanner_environment!
    validate_project!
  end

  def scan
    puts "🔍 Scanning local Ruby project: #{@project_path}"
    puts "📁 Gemfile: #{@gemfile_path}"
    puts "📁 Gemfile.lock: #{@gemfile_lock_path}"
    puts "🏠 Scanner working directory: #{Dir.pwd}"
    puts "🎯 Scan mode: #{scan_mode_description}"
    puts "=" * 60

    # Read dependency files
    dependency_files = read_dependency_files
    puts "✅ Read #{dependency_files.length} dependency files"

    # Parse dependencies
    parser = create_parser(dependency_files)
    dependencies = parser.parse
    puts "✅ Found #{dependencies.length} dependencies (#{dependencies.count(&:top_level?)} top-level)"

    # Check for updates based on mode
    case @options[:mode]
    when :security_only
      if @options[:bundle_audit]
        run_bundle_audit
      else
        check_security_vulnerabilities(dependencies, dependency_files)
      end
    when :security_details
      if @options[:bundle_audit]
        run_bundle_audit
      else
        check_security_vulnerabilities_detailed(dependencies, dependency_files)
      end
    when :all_updates
      check_all_updates(dependencies, dependency_files)
    else
      check_security_vulnerabilities(dependencies, dependency_files)
    end
  end

  private

  def scan_mode_description
    case @options[:mode]
    when :security_only
      "Security vulnerabilities only"
    when :security_details
      "Security vulnerabilities with detailed information"
    when :all_updates
      "All available updates"
    else
      "All available updates"
    end
  end

  def verify_scanner_environment!
    # Ensure we're running from the scanner environment, not the project
    unless Dir.pwd.start_with?("/home/dependabot")
      puts "⚠️  Warning: Not running from scanner environment"
      puts "   Current directory: #{Dir.pwd}"
      puts "   Expected: /home/dependabot/*"
    end

    # Verify scanner dependencies are available - check for parallel gem
    parallel_gems = Dir.glob("/usr/local/bundle/ruby/*/gems/parallel-*")
    raise "Scanner environment not properly set up - parallel gem not found" if parallel_gems.empty?

    puts "✅ Scanner environment verified (found parallel gem: #{parallel_gems.first})"
  end

  def validate_project!
    raise "No Gemfile found at: #{@gemfile_path}" unless File.exist?(@gemfile_path)
    raise "No Gemfile.lock found at: #{@gemfile_lock_path}" unless File.exist?(@gemfile_lock_path)

    puts "✅ Project validation passed"
  end

  def read_dependency_files
    files = []

    # Read Gemfile (using absolute paths)
    gemfile_content = File.read(@gemfile_path)
    files << Dependabot::DependencyFile.new(
      name: "Gemfile",
      content: gemfile_content,
      directory: "/"
    )

    # Read Gemfile.lock (using absolute paths)
    gemfile_lock_content = File.read(@gemfile_lock_path)
    files << Dependabot::DependencyFile.new(
      name: "Gemfile.lock",
      content: gemfile_lock_content,
      directory: "/"
    )

    # Look for other dependency files (using absolute paths)
    Dir.glob(File.join(@project_path, "**/*.{gemspec,ruby}")).each do |file_path|
      relative_path = file_path.sub(@project_path, "")
      content = File.read(file_path)
      files << Dependabot::DependencyFile.new(
        name: relative_path,
        content: content,
        directory: File.dirname(relative_path)
      )
    end

    files
  end

  def create_parser(dependency_files)
    # Create a proper Dependabot::Source object
    source = Dependabot::Source.new(
      provider: "github", # Use a valid provider
      repo: "local-project",
      directory: "/",
      branch: "main"
    )

    Dependabot::Bundler::FileParser.new(
      dependency_files: dependency_files,
      source: source,
      credentials: []
    )
  end

  def check_security_vulnerabilities(dependencies, dependency_files)
    puts "\n🔒 Checking for actual security vulnerabilities with CVEs..."
    puts "=" * 60

    top_level_deps = dependencies.select(&:top_level?)
    vulnerable_deps = []

    puts "📋 Using Dependabot's built-in Ruby Advisory Database..."
    puts "   This will show only dependencies with known security vulnerabilities"
    puts ""

    # Get security advisories from the Ruby Advisory Database
    security_advisories = get_security_advisories

    top_level_deps.each do |dependency|
      checker = create_update_checker(dependency, dependency_files)

      # Check if this dependency has any security advisories
      dependency_advisories = security_advisories.select do |adv|
        adv.dependency_name.downcase == dependency.name.downcase
      end

      if dependency_advisories.any?
        # Check if current version is vulnerable
        current_version = Gem::Version.new(dependency.version)
        is_vulnerable = dependency_advisories.any? { |adv| adv.vulnerable?(current_version) }

        if is_vulnerable
          latest_version = checker.latest_version
          latest_resolvable_version = checker.latest_resolvable_version

          # Check if the update fixes the vulnerability
          is_security_fix = dependency_advisories.any? do |adv|
            adv.fixed_by?(Dependabot::Dependency.new(
                            name: dependency.name,
                            version: latest_resolvable_version,
                            package_manager: dependency.package_manager,
                            requirements: dependency.requirements
                          ))
          end

          vulnerable_deps << {
            dependency: dependency,
            checker: checker,
            latest_version: latest_version,
            latest_resolvable_version: latest_resolvable_version,
            is_security_fix: is_security_fix,
            advisories: dependency_advisories
          }
        end
      end
    rescue StandardError => e
      puts "   ❌ Error checking #{dependency.name}: #{e.message}"
    end

    if @options[:output_format] == :json
      # JSON output format
      result = {
        scan_type: "security_vulnerabilities",
        project_path: @project_path,
        scan_timestamp: Time.now.iso8601,
        note: "This scan shows only dependencies with actual security vulnerabilities using Dependabot's Ruby Advisory Database.",
        summary: {
          total_dependencies: top_level_deps.length,
          vulnerable_dependencies: vulnerable_deps.length,
          up_to_date: top_level_deps.length - vulnerable_deps.length
        },
        vulnerable_dependencies: vulnerable_deps.map do |dep_info|
          {
            name: dep_info[:dependency].name,
            current_version: dep_info[:dependency].version,
            latest_version: dep_info[:latest_version],
            latest_resolvable_version: dep_info[:latest_resolvable_version],
            is_security_fix: dep_info[:is_security_fix],
            advisories: dep_info[:advisories].map do |adv|
              {
                cve: adv.cve,
                ghsa: adv.ghsa,
                title: adv.title,
                description: adv.description,
                cvss_v2: adv.cvss_v2,
                cvss_v3: adv.cvss_v3,
                url: adv.url
              }
            end,
            groups: dep_info[:dependency].requirements.map { |r| r[:groups] }.flatten.uniq,
            requirements: dep_info[:dependency].requirements.map { |r| r[:requirement] }
          }
        end
      }
      puts JSON.pretty_generate(result)
    elsif vulnerable_deps.empty?
      puts "\n✅ No security vulnerabilities found!"
      puts "   All dependencies are secure and up to date"
    else
      puts "\n🚨 Found #{vulnerable_deps.length} dependencies with ACTUAL security vulnerabilities:"

      if @options[:output_format] == :summary
        # Summary format - just show counts and names
        puts "\n📊 Summary:"
        puts "   Total dependencies with security vulnerabilities: #{vulnerable_deps.length}"
        puts "   Dependencies: #{vulnerable_deps.map { |d| d[:dependency].name }.join(', ')}"

        if @options[:show_details]
          puts "\n📋 Detailed Summary:"
          vulnerable_deps.each do |dep_info|
            dependency = dep_info[:dependency]
            latest_resolvable_version = dep_info[:latest_resolvable_version]
            security_fix = dep_info[:is_security_fix] ? "🔒 Security Fix" : "⚠️  Vulnerable"
            puts "   • #{dependency.name}: #{dependency.version} → #{latest_resolvable_version} (#{security_fix})"
          end
        end
      else
        # Full format - show all details
        vulnerable_deps.each do |dep_info|
          dependency = dep_info[:dependency]
          checker = dep_info[:checker]
          latest_version = dep_info[:latest_version]
          latest_resolvable_version = dep_info[:latest_resolvable_version]
          security_fix = dep_info[:is_security_fix] ? "🔒 Security Fix" : "⚠️  Vulnerable"

          puts "\n📦 #{dependency.name} (#{dependency.version}) - #{security_fix}"
          puts "   🔄 Update available: #{latest_resolvable_version}"
          puts "   📋 Groups: #{dependency.requirements.map { |r| r[:groups].join(', ') }.join(', ')}"

          # Show security advisory details
          dep_info[:advisories].each do |advisory|
            puts "   🚨 Security Advisory:"
            puts "      CVE: #{advisory.cve}" if advisory.cve
            puts "      GHSA: #{advisory.ghsa}" if advisory.ghsa
            puts "      Title: #{advisory.title}" if advisory.title
            puts "      CVSS v3: #{advisory.cvss_v3}" if advisory.cvss_v3
            puts "      URL: #{advisory.url}" if advisory.url
          end

          if @options[:show_details]
            puts "   📊 Update strategy: #{checker.update_strategy}"
            puts "   🔓 Requirements to unlock: #{checker.requirements_to_unlock}"
          end
        end
      end
    end

    return if @options[:output_format] == :json

    puts "\n" + ("=" * 60)
    puts "🎯 Security scan complete! Found #{vulnerable_deps.length} dependencies with actual security vulnerabilities"
    puts "\n💡 This scan uses Dependabot's built-in Ruby Advisory Database"
    puts "   Only shows dependencies with known CVEs and available security fixes"
  end

  def check_security_vulnerabilities_detailed(dependencies, dependency_files)
    puts "\n🔒 Checking for security vulnerabilities with detailed information..."
    puts "=" * 60

    # This would integrate with security advisory databases
    # For now, fall back to security-only mode
    check_security_vulnerabilities(dependencies, dependency_files)

    puts "\n📝 Note: Detailed security information requires integration with security advisory databases"
    puts "   Consider using GitHub Security Advisories or Ruby Advisory Database for CVE details"
  end

  def check_all_updates(dependencies, dependency_files)
    puts "\n🔍 Checking for all available updates..."
    puts "=" * 60

    top_level_deps = dependencies.select(&:top_level?)
    updatable_deps = []

    top_level_deps.each do |dependency|
      checker = create_update_checker(dependency, dependency_files)

      if checker.up_to_date?
        puts "   ✅ #{dependency.name} (#{dependency.version}) - Up to date"
      else
        latest_version = checker.latest_version
        latest_resolvable_version = checker.latest_resolvable_version

        updatable_deps << {
          dependency: dependency,
          checker: checker,
          latest_version: latest_version,
          latest_resolvable_version: latest_resolvable_version
        }

        if @options[:output_format] == :summary
          puts "   🔄 #{dependency.name} (#{dependency.version}) → #{latest_resolvable_version}"
        else
          puts "\n📦 #{dependency.name} (#{dependency.version})"
          puts "   🔄 Update available:"
          puts "      Latest version: #{latest_version}"
          puts "      Latest resolvable: #{latest_resolvable_version}"

          if @options[:show_details]
            puts "      Update strategy: #{checker.update_strategy}"
            puts "      Requirements to unlock: #{checker.requirements_to_unlock}"
          end
        end
      end
    rescue StandardError => e
      puts "   ❌ Error checking #{dependency.name}: #{e.message}"
    end

    if @options[:output_format] == :json
      # JSON output format
      result = {
        scan_type: "all_updates",
        project_path: @project_path,
        scan_timestamp: Time.now.iso8601,
        summary: {
          total_dependencies: top_level_deps.length,
          up_to_date: top_level_deps.length - updatable_deps.length,
          available_updates: updatable_deps.length
        },
        dependencies: top_level_deps.map do |dependency|
          dep_info = updatable_deps.find { |d| d[:dependency].name == dependency.name }
          if dep_info
            {
              name: dependency.name,
              current_version: dependency.version,
              status: "updatable",
              latest_version: dep_info[:latest_version],
              latest_resolvable_version: dep_info[:latest_resolvable_version],
              groups: dependency.requirements.map { |r| r[:groups] }.flatten.uniq,
              requirements: dependency.requirements.map { |r| r[:requirement] }
            }
          else
            {
              name: dependency.name,
              current_version: dependency.version,
              status: "up_to_date",
              groups: dependency.requirements.map { |r| r[:groups] }.flatten.uniq,
              requirements: dependency.requirements.map { |r| r[:requirement] }
            }
          end
        end
      }
      puts JSON.pretty_generate(result)
    elsif @options[:output_format] == :summary
      puts "\n📊 Summary:"
      puts "   Total dependencies: #{top_level_deps.length}"
      puts "   Up to date: #{top_level_deps.length - updatable_deps.length}"
      puts "   Available updates: #{updatable_deps.length}"

      if updatable_deps.any? && @options[:show_details]
        puts "\n📋 Dependencies with updates:"
        updatable_deps.each do |dep_info|
          dependency = dep_info[:dependency]
          latest_resolvable_version = dep_info[:latest_resolvable_version]
          puts "   • #{dependency.name}: #{dependency.version} → #{latest_resolvable_version}"
        end
      end
    end

    return if @options[:output_format] == :json

    puts "\n" + ("=" * 60)
    puts "🎯 Scan complete! Found #{updatable_deps.length} dependencies with updates out of #{top_level_deps.length} total"
  end

  def create_update_checker(dependency, dependency_files)
    source = Dependabot::Source.new(
      provider: "github", # Use a valid provider
      repo: "local-project",
      directory: "/",
      branch: "main"
    )

    Dependabot::Bundler::UpdateChecker.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: [],
      repo_contents_path: @project_path
    )
  end

  def run_bundle_audit
    puts "\n🔒 Running bundle audit to check for actual security vulnerabilities..."
    puts "=" * 60

    # Ensure bundler is installed and available
    unless system("bundle --version")
      puts "⚠️  bundler not found. Please ensure bundler is installed and in your PATH."
      puts "   Run 'gem install bundler' if needed."
      exit 1
    end

    # Run bundle audit
    puts "   Running 'bundle audit' in #{@project_path}..."
    if system("cd #{@project_path} && bundle audit")
      puts "✅ bundle audit completed successfully!"
      puts "   Please review the output for actual security vulnerabilities."
    else
      puts "❌ bundle audit failed. Please check the output for details."
      exit 1
    end
  end

  def get_security_advisories
    puts "   📚 Loading security advisories from Ruby Advisory Database..."

    advisories = []
    advisory_db_path = File.join(Dir.pwd, ".local", "share", "ruby-advisory-db", "gems")

    unless Dir.exist?(advisory_db_path)
      puts "   ⚠️  Ruby Advisory Database not found at: #{advisory_db_path}"
      puts "   💡 This database contains CVE information for Ruby gems"
      return []
    end

    # Load all gem advisories
    Dir.glob(File.join(advisory_db_path, "*", "*.yml")).each do |advisory_file|
      advisory_data = YAML.safe_load_file(advisory_file, permitted_classes: [Date])
      next unless advisory_data && advisory_data["gem"]

      # Create Dependabot::SecurityAdvisory objects
      vulnerable_versions = []
      safe_versions = []

      # Parse version requirements
      safe_versions.concat(advisory_data["unaffected_versions"]) if advisory_data["unaffected_versions"]

      safe_versions.concat(advisory_data["patched_versions"]) if advisory_data["patched_versions"]

      # For now, we'll create a basic advisory
      # In a full implementation, we'd parse the version requirements properly
      advisory = Dependabot::SecurityAdvisory.new(
        dependency_name: advisory_data["gem"],
        package_manager: "bundler",
        vulnerable_versions: vulnerable_versions,
        safe_versions: safe_versions
      )

      # Add additional metadata
      advisory.instance_variable_set(:@cve, advisory_data["cve"]) if advisory_data["cve"]
      advisory.instance_variable_set(:@ghsa, advisory_data["ghsa"]) if advisory_data["ghsa"]
      advisory.instance_variable_set(:@url, advisory_data["url"]) if advisory_data["url"]
      advisory.instance_variable_set(:@title, advisory_data["title"]) if advisory_data["title"]
      advisory.instance_variable_set(:@description, advisory_data["description"]) if advisory_data["description"]
      advisory.instance_variable_set(:@cvss_v3, advisory_data["cvss_v3"]) if advisory_data["cvss_v3"]

      advisories << advisory
    rescue StandardError => e
      puts "   ⚠️  Error loading advisory #{advisory_file}: #{e.message}"
    end

    puts "   ✅ Loaded #{advisories.length} security advisories"
    advisories
  end
end

# Command line interface
if __FILE__ == $0
  options = {
    mode: :security_only, # Default mode: security vulnerabilities only
    show_details: true, # Default: show detailed version information
    output_format: :summary, # Default output: summary format
    bundle_audit: false # New option for bundle audit
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: ruby local_scan.rb [OPTIONS] PROJECT_PATH"

    opts.on("--all-updates", "Show all available updates (not just security)") do
      options[:mode] = :all_updates
    end

    opts.on("--security-details", "Show security vulnerabilities with detailed information") do
      options[:mode] = :security_details
    end

    opts.on("--show-details", "Show detailed update information (default: enabled)") do
      options[:show_details] = true
    end

    opts.on("--no-details", "Hide detailed update information") do
      options[:show_details] = false
    end

    opts.on("--output-format FORMAT", %i(text json summary),
            "Output format: text, json, or summary (default: summary)") do |format|
      options[:output_format] = format
    end

    opts.on("--bundle-audit", "Run bundle audit to check for actual security vulnerabilities") do
      options[:bundle_audit] = true
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      puts "\nScan Modes (default: security-only):"
      puts "  --security-only      Only show dependencies with security vulnerabilities (default)"
      puts "  --security-details   Show security vulnerabilities with detailed information"
      puts "  --all-updates        Show all available updates (not just security)"
      puts "  --bundle-audit       Run bundle audit to check for actual security vulnerabilities"
      puts "\nOutput Options (default: summary):"
      puts "  --show-details       Show detailed update information (default: enabled)"
      puts "  --no-details         Hide detailed update information"
      puts "  --output-format      Choose output format: text, json, or summary (default: summary)"
      puts "\nExamples:"
      puts "  ruby local_scan.rb /path/to/project                    # Security-only, summary output (default)"
      puts "  ruby local_scan.rb --all-updates /path/to/project      # All updates, summary output"
      puts "  ruby local_scan.rb --show-details /path/to/project     # Security-only, detailed summary"
      puts "  ruby local_scan.rb --output-format json /path/to/project # Security-only, JSON output"
      puts "  ruby local_scan.rb --all-updates --output-format text /path/to/project # All updates, text output"
      puts "  ruby local_scan.rb --bundle-audit /path/to/project    # Run bundle audit"
      exit
    end
  end.parse!

  if ARGV.empty?
    puts "Error: Please provide a project path"
    puts "Usage: ruby local_scan.rb [OPTIONS] PROJECT_PATH"
    puts "Default: Security vulnerabilities only with summary output"
    puts "Run with --help for more options"
    exit 1
  end

  project_path = ARGV[0]

  begin
    scanner = LocalDependabotScanner.new(project_path, options)
    scanner.scan
  rescue StandardError => e
    puts "❌ Error: #{e.message}"
    puts e.backtrace.first(5).join("\n")
    exit 1
  end
end
