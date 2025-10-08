# typed: strict
# frozen_string_literal: true

require "json"
require_relative "base_updater"

# Updates GitHub workflow and configuration files for a new ecosystem
class GitHubWorkflowUpdater < BaseUpdater
  extend T::Sig

  # Keys that should appear first in ci-filters.yml
  FIRST_KEYS = T.let(%w(shared rakefile_tests dry_run).freeze, T::Array[String])

  sig { void }
  def update_all
    update_ci_filters
    update_smoke_filters
    update_smoke_matrix
    update_ci_workflow
    update_images_branch_workflow
    update_images_latest_workflow
    update_issue_labeler
  end

  private

  sig { void }
  def update_ci_filters
    file = ".github/ci-filters.yml"
    return unless file_exists?(file)

    content = File.read(file)

    # Check if ecosystem already exists
    if content.match?(/^#{Regexp.escape(ecosystem_name)}:/)
      skip_message(file, "ecosystem already exists")
      return
    end

    # Create new entry preserving original formatting style
    new_entry = "#{ecosystem_name}:\n  - *shared\n  - '#{ecosystem_name}/**'\n"

    # Find correct alphabetical position after FIRST_KEYS
    lines = content.lines
    insert_index = lines.size

    # Find insertion point - after FIRST_KEYS, in alphabetical order
    lines.each_with_index do |line, idx|
      # Check if this is a key line (not indented, ends with colon)
      next unless line.match?(/^[a-z_]+:/)

      key = line[/^([a-z_]+):/, 1]
      next if FIRST_KEYS.include?(key)

      # Found a non-FIRST_KEY, check if it should come after our ecosystem
      if key && key > ecosystem_name
        insert_index = idx
        break
      end
    end

    lines.insert(insert_index, new_entry)
    write_file(file, lines.join)
    record_change(file, "Added #{ecosystem_name} filters")
    success_message(file)
  end

  sig { void }
  def update_smoke_filters
    file = ".github/smoke-filters.yml"
    return unless file_exists?(file)

    content = File.read(file)

    # Check if ecosystem already exists
    if content.match?(/^#{Regexp.escape(ecosystem_name)}:/)
      skip_message(file, "ecosystem already exists")
      return
    end

    # Create new entry preserving original formatting style
    new_entry = "#{ecosystem_name}:\n  - *common\n  - '#{ecosystem_name}/**'\n"

    # Find correct alphabetical position after 'common'
    lines = content.lines
    insert_index = lines.size

    # Find insertion point - after 'common', in alphabetical order
    found_common = T.let(false, T::Boolean)
    lines.each_with_index do |line, idx|
      # Check if this is a key line (not indented, ends with colon)
      next unless line.match?(/^[a-z_]+:/)

      key = line[/^([a-z_]+):/, 1]

      if key == "common"
        found_common = true
        next
      end

      # Skip until we've found common
      next unless found_common

      # Found a non-common key, check if it should come after our ecosystem
      if key && key > ecosystem_name
        insert_index = idx
        break
      end
    end

    lines.insert(insert_index, new_entry)
    write_file(file, lines.join)
    record_change(file, "Added #{ecosystem_name} filters")
    success_message(file)
  end

  sig { void }
  def update_smoke_matrix
    file = ".github/smoke-matrix.json"
    return unless file_exists?(file)

    matrix = JSON.parse(File.read(file))

    if matrix.any? { |entry| entry["core"] == ecosystem_name }
      skip_message(file, "ecosystem already exists")
      return
    end

    ecosystem_str = ecosystem_name.tr("_", "-")
    test_str = ecosystem_str

    matrix << {
      "core" => ecosystem_name,
      "test" => test_str,
      "ecosystem" => ecosystem_str
    }

    matrix.sort_by! { |entry| entry["core"] }

    write_file(file, JSON.pretty_generate(matrix) + "\n")
    record_change(file, "Added #{ecosystem_name} matrix entry")
    success_message(file)
  end

  sig { void }
  def update_ci_workflow
    file = ".github/workflows/ci.yml"
    return unless file_exists?(file)

    content = File.read(file)

    if content.include?("- { path: #{ecosystem_name},")
      skip_message(file, "ecosystem already exists")
      return
    end

    lines = content.lines
    suite_index = lines.index { |line| line.include?("suite:") }

    if suite_index
      update_ci_workflow_matrix(lines, suite_index, file)
    else
      warning_message(file, "Could not find matrix.suite section")
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
    success_message(file)
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
    return unless file_exists?(file)

    content = File.read(file)

    if content.include?("- { name: #{ecosystem_name},")
      skip_message(file, "ecosystem already exists")
      return
    end

    lines = content.lines
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
      last_suite_index = suite_start_index
      ((suite_start_index + 1)...lines.size).each do |i|
        break unless T.must(lines[i]).match?(/^\s+- \{/)

        last_suite_index = i
      end

      ecosystem_str = ecosystem_name.tr("_", "-")
      new_entry = "          - { name: #{ecosystem_name}, ecosystem: #{ecosystem_str} }\n"

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
      success_message(file)
    else
      warning_message(file, "Could not find matrix.suite section")
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
  sig { void }
  def update_images_latest_workflow
    file = ".github/workflows/images-latest.yml"
    return unless file_exists?(file)

    content = File.read(file)

    if content.include?("- { name: #{ecosystem_name},")
      skip_message(file, "ecosystem already exists")
      return
    end

    lines = content.lines
    suite_start_index = -1

    lines.each_with_index do |line, idx|
      next unless line.include?("matrix:") && idx.positive? && T.must(lines[(idx - 10)..idx]).any? do |l|
        l.include?("push-updater-image")
      end

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
      last_suite_index = suite_start_index
      ((suite_start_index + 1)...lines.size).each do |i|
        break unless T.must(lines[i]).match?(/^\s+- \{/)

        last_suite_index = i
      end

      ecosystem_str = ecosystem_name.tr("_", "-")
      new_entry = "          - { name: #{ecosystem_name}, ecosystem: #{ecosystem_str} }\n"

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
      success_message(file)
    else
      warning_message(file, "Could not find matrix.suite section")
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity

  sig { void }
  def update_issue_labeler
    file = ".github/issue-labeler.yml"
    return unless file_exists?(file)

    content = File.read(file)

    label_parts = ecosystem_name.split("_")
    label = if label_parts.size > 1
              "\"L: #{label_parts[0]}:#{T.must(label_parts[1..-1]).join('-')}\""
            else
              "\"L: #{ecosystem_name}\""
            end

    if content.include?(label)
      skip_message(file, "ecosystem already exists")
      return
    end

    new_entry = "\n#{label}:\n    - '(#{ecosystem_name})'\n"

    # Append to the end of the file
    content += new_entry
    write_file(file, content)
    record_change(file, "Added #{ecosystem_name} issue label")
    success_message(file)
  end
end
