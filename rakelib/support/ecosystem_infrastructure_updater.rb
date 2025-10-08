# typed: strict
# frozen_string_literal: true

require "fileutils"
require "yaml"
require "json"
require "sorbet-runtime"

# Class that updates supporting infrastructure files for a new ecosystem
# rubocop:disable Metrics/ClassLength
class EcosystemInfrastructureUpdater
  extend T::Sig

  # Keys that should appear first in ci-filters.yml
  FIRST_KEYS = T.let(%w(shared rakefile_tests dry_run).freeze, T::Array[String])

  # Ecosystems to skip when sorting in script/dependabot
  SKIP_ECOSYSTEMS = T.let(%w(updater bin common).freeze, T::Array[String])

  sig { params(name: String, overwrite_mode: String).void }
  def initialize(name, overwrite_mode = "ask")
    @ecosystem_name = T.let(name, String)
    @ecosystem_module = T.let(name.split("_").map(&:capitalize).join, String)
    @initial_overwrite_mode = T.let(overwrite_mode, String)
    @changes_made = T.let([], T::Array[String])
  end

  sig { void }
  def update_infrastructure
    puts "Updating supporting infrastructure for ecosystem: #{@ecosystem_name}"
    puts "Overwrite mode: #{@initial_overwrite_mode}"
    puts ""

    # Detect ecosystem configuration
    unless ecosystem_exists?
      puts "Error: Ecosystem '#{@ecosystem_name}' not found. Please scaffold it first."
      exit 1
    end

    # Update each infrastructure component
    update_ci_filters
    update_smoke_filters
    update_smoke_matrix
    update_ci_workflow
    update_images_branch_workflow
    update_images_latest_workflow
    update_issue_labeler
    update_docker_dev_shell
    update_dry_run_script
    update_script_dependabot
    update_omnibus
    update_setup_rb
    update_helpers_gemspecs

    print_summary
  end

  private

  sig { returns(String) }
  attr_reader :ecosystem_name

  sig { returns(String) }
  attr_reader :ecosystem_module

  sig { returns(String) }
  attr_reader :initial_overwrite_mode

  sig { returns(T::Array[String]) }
  attr_reader :changes_made

  sig { params(file: String, description: String).void }
  def record_change(file, description)
    @changes_made << "#{file}: #{description}"
  end

  sig { returns(T::Boolean) }
  def ecosystem_exists?
    # Check if the ecosystem directory exists
    ecosystem_dir = "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}.rb"
    File.exist?(ecosystem_dir)
  end

  sig { params(file: String, content: String).void }
  def write_file(file, content)
    File.write(file, content)
  end

  sig { void }
  def update_ci_filters
    file = ".github/ci-filters.yml"
    return unless File.exist?(file)

    yaml = YAML.load_file(file, aliases: true)

    # Check if ecosystem already exists
    if yaml.key?(ecosystem_name)
      puts "  ⊘ Skipped #{file} (ecosystem already exists)"
      return
    end

    # Add new ecosystem entry
    yaml[ecosystem_name] = [
      yaml["shared"],
      "#{ecosystem_name}/**"
    ]

    # Sort keys alphabetically (excluding 'shared' and 'rakefile_tests' which should be first)
    sorted_yaml = {}
    sorted_yaml["shared"] = yaml["shared"]
    sorted_yaml["rakefile_tests"] = yaml["rakefile_tests"] if yaml.key?("rakefile_tests")
    sorted_yaml["dry_run"] = yaml["dry_run"] if yaml.key?("dry_run")

    yaml.keys.reject { |k| FIRST_KEYS.include?(k) }.sort.each do |key|
      sorted_yaml[key] = yaml[key]
    end

    write_file(file, YAML.dump(sorted_yaml))
    record_change(file, "Added #{ecosystem_name} filters")
    puts "  ✓ Updated #{file}"
  end

  sig { void }
  def update_smoke_filters
    file = ".github/smoke-filters.yml"
    return unless File.exist?(file)

    yaml = YAML.load_file(file, aliases: true)

    # Check if ecosystem already exists
    if yaml.key?(ecosystem_name)
      puts "  ⊘ Skipped #{file} (ecosystem already exists)"
      return
    end

    # Add new ecosystem entry
    yaml[ecosystem_name] = [
      yaml["common"],
      "#{ecosystem_name}/**"
    ]

    # Sort keys alphabetically (excluding 'common' which should be first)
    sorted_yaml = { "common" => yaml["common"] }
    yaml.keys.reject { |k| k == "common" }.sort.each do |key|
      sorted_yaml[key] = yaml[key]
    end

    write_file(file, YAML.dump(sorted_yaml))
    record_change(file, "Added #{ecosystem_name} filters")
    puts "  ✓ Updated #{file}"
  end

  sig { void }
  def update_smoke_matrix
    file = ".github/smoke-matrix.json"
    return unless File.exist?(file)

    matrix = JSON.parse(File.read(file))

    # Check if ecosystem already exists
    if matrix.any? { |entry| entry["core"] == ecosystem_name }
      puts "  ⊘ Skipped #{file} (ecosystem already exists)"
      return
    end

    # Determine ecosystem string based on name
    ecosystem_str = ecosystem_name.tr("_", "-")
    test_str = ecosystem_str

    # Add new ecosystem entry
    matrix << {
      "core" => ecosystem_name,
      "test" => test_str,
      "ecosystem" => ecosystem_str
    }

    # Sort by core name
    matrix.sort_by! { |entry| entry["core"] }

    write_file(file, JSON.pretty_generate(matrix) + "\n")
    record_change(file, "Added #{ecosystem_name} matrix entry")
    puts "  ✓ Updated #{file}"
  end

  sig { void }
  def update_ci_workflow
    file = ".github/workflows/ci.yml"
    return unless File.exist?(file)

    content = File.read(file)

    # Check if ecosystem already exists
    if content.include?("- { path: #{ecosystem_name},")
      puts "  ⊘ Skipped #{file} (ecosystem already exists)"
      return
    end

    # Find the matrix.suite section and add new entry
    lines = content.lines
    suite_index = lines.index { |line| line.include?("suite:") }

    if suite_index
      update_ci_workflow_matrix(lines, suite_index, file)
    else
      puts "  ⚠ Warning: Could not find matrix.suite section in #{file}"
    end
  end

  sig { params(lines: T::Array[String], suite_index: Integer, file: String).void }
  def update_ci_workflow_matrix(lines, suite_index, file)
    last_suite_index = find_last_suite_index(lines, suite_index)
    new_entry = create_ci_suite_entry
    insert_index = find_ci_insert_position(lines, suite_index, last_suite_index)

    lines.insert(insert_index, new_entry)
    write_file(file, lines.join)
    record_change(file, "Added #{ecosystem_name} to CI matrix")
    puts "  ✓ Updated #{file}"
  end

  sig { params(lines: T::Array[String], suite_index: Integer).returns(Integer) }
  def find_last_suite_index(lines, suite_index)
    last_index = suite_index
    ((suite_index + 1)...lines.size).each do |i|
      break unless T.must(lines[i]).match?(/^\s*- \{/)

      last_index = i
    end
    last_index
  end

  sig { returns(String) }
  def create_ci_suite_entry
    ecosystem_str = ecosystem_name.tr("_", "-")
    "          - { path: #{ecosystem_name}, name: #{ecosystem_name}, ecosystem: #{ecosystem_str} }\n"
  end

  sig { params(lines: T::Array[String], suite_index: Integer, last_suite_index: Integer).returns(Integer) }
  def find_ci_insert_position(lines, suite_index, last_suite_index)
    insert_index = suite_index + 1
    while insert_index <= last_suite_index
      line = lines[insert_index]
      if line =~ /- \{ path: (\w+),/
        existing_name = ::Regexp.last_match(1)
        break if T.must(existing_name) > ecosystem_name
      end
      insert_index += 1
    end
    insert_index
  end
  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity
  sig { void }
  def update_images_branch_workflow
    file = ".github/workflows/images-branch.yml"
    return unless File.exist?(file)

    content = File.read(file)

    if content.include?("- { name: #{ecosystem_name},")
      puts "  ⊘ Skipped #{file} (ecosystem already exists)"
      return
    end

    lines = content.lines

    # Find the suite: line in the push-updater-images job
    suite_start_index = -1
    in_push_updater_images = T.let(false, T::Boolean)

    lines.each_with_index do |line, idx|
      in_push_updater_images = true if line.include?("push-updater-images:")

      if in_push_updater_images && line.strip == "suite:"
        suite_start_index = idx
        break
      end
    end

    if suite_start_index >= 0
      # Find the last suite entry
      last_suite_index = suite_start_index
      ((suite_start_index + 1)...lines.size).each do |i|
        break unless T.must(lines[i]).match?(/^\s+- \{/)

        last_suite_index = i
      end

      ecosystem_str = ecosystem_name.tr("_", "-")
      new_entry = "          - { name: #{ecosystem_name}, ecosystem: #{ecosystem_str} }\n"

      # Find correct alphabetical position
      insert_index = suite_start_index + 1
      while insert_index <= last_suite_index
        line = lines[insert_index]
        if line =~ /- \{ name: (\w+),/
          existing_name = ::Regexp.last_match(1)
          break if T.must(existing_name) > ecosystem_name
        end
        insert_index += 1
      end

      lines.insert(insert_index, new_entry)
      write_file(file, lines.join)
      record_change(file, "Added #{ecosystem_name} to images-branch matrix")
      puts "  ✓ Updated #{file}"
    else
      puts "  ⚠ Warning: Could not find matrix.suite section in #{file}"
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
  sig { void }
  def update_images_latest_workflow
    file = ".github/workflows/images-latest.yml"
    return unless File.exist?(file)

    content = File.read(file)

    if content.include?("- { name: #{ecosystem_name},")
      puts "  ⊘ Skipped #{file} (ecosystem already exists)"
      return
    end

    lines = content.lines

    # Find the matrix suite section within push-updater-image job
    suite_start_index = -1
    lines.each_with_index do |line, idx|
      next unless line.include?("matrix:") && idx.positive? && T.must(lines[(idx - 10)..idx]).any? do |l|
        l.include?("push-updater-image")
      end

      # Look for suite: line after matrix:
      ((idx + 1)...lines.size).each do |j|
        if T.must(lines[j]).include?("suite:")
          suite_start_index = j
          break
        end
        break if T.must(lines[j]).strip.empty? || !T.must(lines[j]).start_with?(" ")
      end
      break if suite_start_index >= 0
    end

    if suite_start_index >= 0
      # Find the last suite entry
      last_suite_index = suite_start_index
      ((suite_start_index + 1)...lines.size).each do |i|
        break unless T.must(lines[i]).match?(/^\s+- \{/)

        last_suite_index = i
      end

      ecosystem_str = ecosystem_name.tr("_", "-")
      new_entry = "          - { name: #{ecosystem_name}, ecosystem: #{ecosystem_str} }\n"

      # Find correct alphabetical position
      insert_index = suite_start_index + 1
      while insert_index <= last_suite_index
        line = lines[insert_index]
        if line =~ /- \{ name: (\w+),/
          existing_name = ::Regexp.last_match(1)
          break if T.must(existing_name) > ecosystem_name
        end
        insert_index += 1
      end

      lines.insert(insert_index, new_entry)
      write_file(file, lines.join)
      record_change(file, "Added #{ecosystem_name} to images-latest matrix")
      puts "  ✓ Updated #{file}"
    else
      puts "  ⚠ Warning: Could not find matrix.suite section in #{file}"
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity

  sig { void }
  def update_issue_labeler
    file = ".github/issue-labeler.yml"
    return unless File.exist?(file)

    content = File.read(file)

    # Generate label name based on ecosystem name
    label_parts = ecosystem_name.split("_")
    label = if label_parts.size > 1
              # Handle names like "go_modules" -> "L: go:modules"
              "\"L: #{label_parts[0]}:#{T.must(label_parts[1..-1]).join('-')}\""
            else
              "\"L: #{ecosystem_name}\""
            end

    if content.include?(label)
      puts "  ⊘ Skipped #{file} (ecosystem already exists)"
      return
    end

    # Add new label entry - use the ecosystem_name directly in the pattern
    new_entry = "\n#{label}:\n    - '(#{ecosystem_name})'\n"

    # Find correct alphabetical position
    lines = content.lines
    insert_index = lines.size

    lines.each_with_index do |line, idx|
      next unless line.start_with?('"L:')

      if line > new_entry.lines.first
        insert_index = idx
        break
      end
    end

    lines.insert(insert_index, new_entry)
    write_file(file, lines.join)
    record_change(file, "Added #{ecosystem_name} issue label")
    puts "  ✓ Updated #{file}"
  end

  sig { void }
  def update_docker_dev_shell
    file = "bin/docker-dev-shell"
    return unless File.exist?(file)

    content = File.read(file)

    # Check if it needs updating (simple check - assumes the script is already comprehensive)
    if content.include?("ecosystem") || content.include?("ECOSYSTEM")
      puts "  ⊘ Skipped #{file} (script handles all ecosystems dynamically)"
      return
    end

    puts "  ⊘ Skipped #{file} (script handles all ecosystems dynamically)"
  end

  # rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity
  sig { void }
  def update_dry_run_script
    file = "bin/dry-run.rb"
    return unless File.exist?(file)

    content = File.read(file)

    # Check if ecosystem already exists in load paths
    if content.include?("$LOAD_PATH << \"./#{ecosystem_name}/lib\"")
      puts "  ⊘ Skipped #{file} (ecosystem already exists)"
      return
    end

    # Find the LOAD_PATH section and add new entry
    lines = content.lines
    load_path_end = -1

    lines.each_with_index do |line, idx|
      if line.include?("$LOAD_PATH << \"./") && line.include?("/lib\"")
        load_path_end = idx
      elsif load_path_end >= 0 && !line.include?("$LOAD_PATH")
        break
      end
    end

    if load_path_end >= 0
      # Insert in alphabetical order
      new_line = "$LOAD_PATH << \"./#{ecosystem_name}/lib\"\n"

      insert_index = 0
      lines.each_with_index do |line, idx|
        next unless line.include?("$LOAD_PATH << \"./") && line.include?("/lib\"")

        next unless line =~ %r{\$LOAD_PATH << "\./([^/]+)/lib"}

        existing_eco = ::Regexp.last_match(1)
        if T.must(existing_eco) > ecosystem_name
          insert_index = idx
          break
        end
        insert_index = idx + 1
      end

      lines.insert(insert_index, new_line)
      write_file(file, lines.join)
      record_change(file, "Added #{ecosystem_name} to LOAD_PATH")
      puts "  ✓ Updated #{file}"
    else
      puts "  ⚠ Warning: Could not find LOAD_PATH section in #{file}"
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/PerceivedComplexity

  # rubocop:disable Metrics/PerceivedComplexity
  sig { void }
  def update_script_dependabot
    file = "script/dependabot"
    return unless File.exist?(file)

    content = File.read(file)

    if content.include?("\"$(pwd)\"/#{ecosystem_name}:")
      puts "  ⊘ Skipped #{file} (ecosystem already exists)"
      return
    end

    lines = content.lines
    last_volume_index = -1

    lines.each_with_index do |line, idx|
      last_volume_index = idx if line.include?("-v \"$(pwd)\"") && line.include?(":/home/dependabot/")
    end

    if last_volume_index >= 0
      new_line = "  -v \"$(pwd)\"/#{ecosystem_name}:/home/dependabot/#{ecosystem_name} \\\n"

      # Find correct alphabetical position
      insert_index = 0
      lines.each_with_index do |line, idx|
        next unless line.include?("-v \"$(pwd)\"") && line.match(%r{/([^:]+):/home/dependabot/})

        existing_eco = ::Regexp.last_match(1)
        next if SKIP_ECOSYSTEMS.include?(existing_eco)

        if T.must(existing_eco) > ecosystem_name
          insert_index = idx
          break
        end
        insert_index = idx + 1
      end

      lines.insert(insert_index, new_line)
      write_file(file, lines.join)
      record_change(file, "Added #{ecosystem_name} volume mount")
      puts "  ✓ Updated #{file}"
    else
      puts "  ⚠ Warning: Could not find volume mount section in #{file}"
    end
  end

  sig { void }
  def update_omnibus
    file = "omnibus/lib/dependabot/omnibus.rb"
    return unless File.exist?(file)

    content = File.read(file)

    if content.include?("require \"dependabot/#{ecosystem_name}\"")
      puts "  ⊘ Skipped #{file} (ecosystem already exists)"
      return
    end

    lines = content.lines
    new_line = "require \"dependabot/#{ecosystem_name}\"\n"

    # Find correct alphabetical position
    insert_index = lines.size
    lines.each_with_index do |line, idx|
      next unless line.include?("require \"dependabot/")
      next if line.include?("require \"dependabot/omnibus")

      next unless line =~ %r{require "dependabot/([^"]+)"}

      existing_eco = ::Regexp.last_match(1)
      if T.must(existing_eco) > ecosystem_name
        insert_index = idx
        break
      end
      insert_index = idx + 1
    end

    lines.insert(insert_index, new_line)
    write_file(file, lines.join)
    record_change(file, "Added #{ecosystem_name} require statement")
    puts "  ✓ Updated #{file}"
  end

  sig { void }
  def update_setup_rb
    file = "updater/lib/dependabot/setup.rb"
    return unless File.exist?(file)

    content = File.read(file)

    if content.include?("    #{ecosystem_name}|")
      puts "  ⊘ Skipped #{file} (ecosystem already exists)"
      return
    end

    lines = content.lines
    pattern_start, pattern_end = find_app_dirs_pattern_bounds(lines)

    if pattern_start >= 0 && pattern_end >= 0
      update_setup_rb_pattern(lines, pattern_start, pattern_end, file)
    else
      puts "  ⚠ Warning: Could not find app_dirs_pattern section in #{file}"
    end
  end

  sig { params(lines: T::Array[String]).returns([Integer, Integer]) }
  def find_app_dirs_pattern_bounds(lines)
    pattern_start = -1
    pattern_end = -1

    lines.each_with_index do |line, idx|
      pattern_start = idx if line.include?("config.app_dirs_pattern = %r{")
      if pattern_start >= 0 && line.include?(")}")
        pattern_end = idx
        break
      end
    end

    [pattern_start, pattern_end]
  end

  sig { params(lines: T::Array[String], pattern_start: Integer, pattern_end: Integer, file: String).void }
  def update_setup_rb_pattern(lines, pattern_start, pattern_end, file)
    new_line = "    #{ecosystem_name}|\n"
    insert_index = find_setup_rb_insert_position(lines, pattern_start, pattern_end)

    lines.insert(insert_index, new_line)
    write_file(file, lines.join)
    record_change(file, "Added #{ecosystem_name} to app_dirs_pattern")
    puts "  ✓ Updated #{file}"
  end

  sig { params(lines: T::Array[String], pattern_start: Integer, pattern_end: Integer).returns(Integer) }
  def find_setup_rb_insert_position(lines, pattern_start, pattern_end)
    insert_index = pattern_end
    ((pattern_start + 1)...pattern_end).each do |idx|
      line = lines[idx]
      next unless line =~ /^\s+(\w+)\|/

      existing_eco = ::Regexp.last_match(1)
      if T.must(existing_eco) > ecosystem_name
        insert_index = idx
        break
      end
      insert_index = idx + 1 if T.must(existing_eco) < ecosystem_name
    end
    insert_index
  end
  # rubocop:enable Metrics/PerceivedComplexity

  # rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/AbcSize
  sig { void }
  def update_helpers_gemspecs
    file = "rakelib/support/helpers.rb"
    return unless File.exist?(file)

    content = File.read(file)

    if content.include?("#{ecosystem_name}/dependabot-#{ecosystem_name}.gemspec")
      puts "  ⊘ Skipped #{file} (ecosystem already exists)"
      return
    end

    lines = content.lines
    gemspecs_start = -1
    gemspecs_end = -1

    lines.each_with_index do |line, idx|
      gemspecs_start = idx if line.include?("GEMSPECS = T.let(")
      if gemspecs_start >= 0 && line.include?(").freeze,")
        gemspecs_end = idx
        break
      end
    end

    if gemspecs_start >= 0 && gemspecs_end >= 0
      new_line = "      #{ecosystem_name}/dependabot-#{ecosystem_name}.gemspec\n"

      # Find correct alphabetical position
      insert_index = gemspecs_end
      ((gemspecs_start + 1)...gemspecs_end).each do |idx|
        line = lines[idx]
        next unless line =~ %r{^\s+([^/]+)/dependabot-}

        existing_eco = ::Regexp.last_match(1)
        next if existing_eco == "common"

        if T.must(existing_eco) > ecosystem_name
          insert_index = idx
          break
        end
        insert_index = idx + 1 if T.must(existing_eco) < ecosystem_name
      end

      lines.insert(insert_index, new_line)
      write_file(file, lines.join)
      record_change(file, "Added #{ecosystem_name} gemspec")
      puts "  ✓ Updated #{file}"
    else
      puts "  ⚠ Warning: Could not find GEMSPECS section in #{file}"
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/AbcSize

  sig { void }
  def print_summary
    puts ""
    puts "=" * 80
    puts "Infrastructure Update Summary"
    puts "=" * 80
    puts ""

    if @changes_made.empty?
      puts "No changes were made. The ecosystem may already be registered."
    else
      puts "The following files were updated:"
      puts ""
      @changes_made.each do |change|
        puts "  • #{change}"
      end
      puts ""
      puts "Total files updated: #{@changes_made.size}"
    end

    puts ""
    puts "=" * 80
    puts ""
    puts "Next steps:"
    puts "1. Review the changes made to ensure correctness"
    puts "2. Update omnibus gem dependencies: cd omnibus && bundle install"
    puts "3. Update updater dependencies: cd updater && bundle install"
    puts "4. Test the ecosystem with: bin/docker-dev-shell #{ecosystem_name}"
    puts "5. See NEW_ECOSYSTEMS.md for complete implementation guide"
  end
end
# rubocop:enable Metrics/ClassLength
