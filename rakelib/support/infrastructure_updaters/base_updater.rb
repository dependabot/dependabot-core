# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

# Base class for infrastructure updaters
class BaseUpdater
  extend T::Sig

  sig { params(ecosystem_name: String).void }
  def initialize(ecosystem_name)
    @ecosystem_name = T.let(ecosystem_name, String)
    @changes_made = T.let([], T::Array[String])
  end

  sig { returns(String) }
  attr_reader :ecosystem_name

  sig { returns(T::Array[String]) }
  attr_reader :changes_made

  protected

  sig { params(file: String, description: String).void }
  def record_change(file, description)
    @changes_made << "#{file}: #{description}"
  end

  sig { params(file: String, content: String).void }
  def write_file(file, content)
    File.write(file, content)
  end

  sig { params(file: String).returns(T::Boolean) }
  def file_exists?(file)
    File.exist?(file)
  end

  sig { params(file: String, message: String).void }
  def skip_message(file, message)
    puts "  ⊘ Skipped #{file} (#{message})"
  end

  sig { params(file: String, message: String).void }
  def warning_message(file, message)
    puts "  ⚠ Warning: #{message} in #{file}"
  end

  sig { params(file: String).void }
  def success_message(file)
    puts "  ✓ Updated #{file}"
  end
end
