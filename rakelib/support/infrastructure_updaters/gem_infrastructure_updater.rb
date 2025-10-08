# typed: strict
# frozen_string_literal: true

require_relative "base_updater"

# Updates Ruby gem infrastructure files for a new ecosystem
class GemInfrastructureUpdater < BaseUpdater
  extend T::Sig

  sig { void }
  def update_all
    update_omnibus
    update_setup_rb
    update_helpers_gemspecs
  end

  private

  sig { void }
  def update_omnibus
    file = "omnibus/lib/dependabot/omnibus.rb"
    return unless file_exists?(file)

    content = File.read(file)

    if content.include?("require \"dependabot/#{ecosystem_name}\"")
      skip_message(file, "ecosystem already exists")
      return
    end

    lines = content.lines
    new_line = "require \"dependabot/#{ecosystem_name}\"\n"

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
    success_message(file)
  end

  sig { void }
  def update_setup_rb
    file = "updater/lib/dependabot/setup.rb"
    return unless file_exists?(file)

    content = File.read(file)

    if content.include?("    #{ecosystem_name}|")
      skip_message(file, "ecosystem already exists")
      return
    end

    lines = content.lines
    pattern_start, pattern_end = find_app_dirs_pattern_bounds(lines)

    if pattern_start >= 0 && pattern_end >= 0
      update_setup_rb_pattern(lines, pattern_start, pattern_end, file)
    else
      warning_message(file, "Could not find app_dirs_pattern section")
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
    success_message(file)
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

  # rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/AbcSize
  sig { void }
  def update_helpers_gemspecs
    file = "rakelib/support/helpers.rb"
    return unless file_exists?(file)

    content = File.read(file)

    if content.include?("#{ecosystem_name}/dependabot-#{ecosystem_name}.gemspec")
      skip_message(file, "ecosystem already exists")
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
      success_message(file)
    else
      warning_message(file, "Could not find GEMSPECS section")
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/AbcSize
end
