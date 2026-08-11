# typed: strict
# frozen_string_literal: true

require "json"
require_relative "base_updater"

# Updates GitHub workflow and configuration files for a new ecosystem
class GitHubWorkflowUpdater < BaseUpdater
  extend T::Sig

  # Keys that should appear first in ci-filters.yml
  FIRST_KEYS = %w(shared rakefile_tests dry_run).freeze
  BAKE_ECOSYSTEM_ENTRY = /^\s+\{ name = "([^"]+)", image = "([^"]+)",/

  sig { void }
  def update_all
    update_ci_filters
    update_smoke_filters
    update_smoke_matrix
    update_ci_workflow
    update_docker_bake
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

  sig { void }
  def update_docker_bake
    file = "docker-bake.hcl"
    return unless file_exists?(file)

    content = File.read(file)
    image_name = ecosystem_name.tr("_", "-")
    if content.lines.any? { |line| line[BAKE_ECOSYSTEM_ENTRY, 1] == ecosystem_name }
      skip_message(file, "ecosystem already exists")
      return
    end
    if content.lines.any? { |line| line[BAKE_ECOSYSTEM_ENTRY, 2] == image_name }
      warning_message(file, "Image name #{image_name} already exists")
      return
    end

    lines = content.lines
    insert_index = find_docker_bake_insert_position(lines)
    unless insert_index
      warning_message(file, "Could not find ECOSYSTEMS matrix")
      return
    end

    lines.insert(insert_index, docker_bake_entry(image_name))
    write_file(file, lines.join)
    record_change(file, "Added #{ecosystem_name} to published image Bake matrix")
    success_message(file)
  end

  sig { params(lines: T::Array[String]).returns(T.nilable(Integer)) }
  def find_docker_bake_insert_position(lines)
    matrix_index = lines.index { |line| line.strip == 'variable "ECOSYSTEMS" {' }
    return unless matrix_index

    list_index = ((matrix_index + 1)...lines.size).find { |index| T.must(lines[index]).strip == "default = [" }
    return unless list_index

    ((list_index + 1)...lines.size).each do |index|
      line = T.must(lines[index])
      return index if line.strip == "]"

      existing_name = line[BAKE_ECOSYSTEM_ENTRY, 1]
      return index if existing_name && existing_name > ecosystem_name
    end

    nil
  end

  sig { params(image_name: String).returns(String) }
  def docker_bake_entry(image_name)
    "    { name = \"#{ecosystem_name}\", image = \"#{image_name}\", " \
      "dockerfile = \"#{ecosystem_name}/Dockerfile\" },\n"
  end

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
