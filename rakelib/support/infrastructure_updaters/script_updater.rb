# typed: strong
# frozen_string_literal: true

require_relative "base_updater"

# Updates development scripts for a new ecosystem
class ScriptUpdater < BaseUpdater
  extend T::Sig

  # Ecosystems to skip when sorting in script/dependabot
  SKIP_ECOSYSTEMS = T.let(%w(updater bin common).freeze, T::Array[String])

  sig { void }
  def update_all
    update_docker_dev_shell
    update_dry_run_script
    update_script_dependabot
  end

  private

  sig { void }
  def update_docker_dev_shell
    file = "bin/docker-dev-shell"
    return unless file_exists?(file)

    content = File.read(file)

    if content.include?("ecosystem") || content.include?("ECOSYSTEM")
      skip_message(file, "script handles all ecosystems dynamically")
      return
    end

    skip_message(file, "script handles all ecosystems dynamically")
  end

  # rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity
  sig { void }
  def update_dry_run_script
    file = "bin/dry-run.rb"
    return unless file_exists?(file)

    content = File.read(file)

    if content.include?("$LOAD_PATH << \"./#{ecosystem_name}/lib\"")
      skip_message(file, "ecosystem already exists")
      return
    end

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
      success_message(file)
    else
      warning_message(file, "Could not find LOAD_PATH section")
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/PerceivedComplexity

  # rubocop:disable Metrics/PerceivedComplexity
  sig { void }
  def update_script_dependabot
    file = "script/dependabot"
    return unless file_exists?(file)

    content = File.read(file)

    if content.include?("\"$(pwd)\"/#{ecosystem_name}:")
      skip_message(file, "ecosystem already exists")
      return
    end

    lines = content.lines
    last_volume_index = -1

    lines.each_with_index do |line, idx|
      last_volume_index = idx if line.include?("-v \"$(pwd)\"") && line.include?(":/home/dependabot/")
    end

    if last_volume_index >= 0
      new_line = "  -v \"$(pwd)\"/#{ecosystem_name}:/home/dependabot/#{ecosystem_name} \\\n"

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
      success_message(file)
    else
      warning_message(file, "Could not find volume mount section")
    end
  end
  # rubocop:enable Metrics/PerceivedComplexity
end
