require "gemnasium/parser"
require "./app/dependency_file"
require "tmpdir"
require "bundler"
require "./lib/shared_helpers"

module DependencyFileUpdaters
  class RubyDependencyFileUpdater
    attr_reader :gemfile, :gemfile_lock, :dependency

    def initialize(dependency_files:, dependency:)
      @gemfile = dependency_files.find { |f| f.name == "Gemfile" }
      @gemfile_lock = dependency_files.find { |f| f.name == "Gemfile.lock" }
      validate_files_are_present!

      @dependency = dependency
    end

    def updated_dependency_files
      [updated_gemfile, updated_gemfile_lock]
    end

    def updated_gemfile
      DependencyFile.new(
        name: "Gemfile",
        content: updated_gemfile_content
      )
    end

    def updated_gemfile_lock
      DependencyFile.new(
        name: "Gemfile.lock",
        content: updated_gemfile_lock_content
      )
    end

    private

    def validate_files_are_present!
      raise "No Gemfile!" unless gemfile
      raise "No Gemfile.lock!" unless gemfile_lock
    end

    def updated_gemfile_content
      return @updated_gemfile_content if @updated_gemfile_content

      gemfile.content.
        to_enum(:scan, Gemnasium::Parser::Patterns::GEM_CALL).
        find { Regexp.last_match[:name] == dependency.name }

      original_gem_declaration_string = $&
      updated_gem_declaration_string =
        original_gem_declaration_string.sub(/[\d\.]+/) do |old_version|
          precision = old_version.split(".").count
          dependency.version.split(".").first(precision).join(".")
        end

      @updated_gemfile_content = gemfile.content.gsub(
        original_gem_declaration_string,
        updated_gem_declaration_string
      )
    end

    def updated_gemfile_lock_content
      return @updated_gemfile_lock_content if @updated_gemfile_lock_content

      SharedHelpers.in_a_temporary_directory do |dir|
        File.write(File.join(dir, "Gemfile"), updated_gemfile_content)
        File.write(File.join(dir, "Gemfile.lock"), gemfile_lock.content)
        Bundler.with_clean_env do
          Bundler::SharedHelpers.chdir(dir) do
            definition = Bundler.definition(gems: [dependency.name])
            definition.resolve_remotely!
            @updated_gemfile_lock_content = definition.to_lock
          end
        end
      end

      @updated_gemfile_lock_content
    end
  end
end
