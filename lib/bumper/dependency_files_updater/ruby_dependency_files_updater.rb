require "gemnasium/parser"
require "bumper/dependency_file"
require "tmpdir"
require "bundler"

module DependencyFilesUpdater
  # NOTE: in ruby a requirement is a matcher and version
  # e.g. "~> 1.2.3", where "~>" is the match
  class RubyDependencyFilesUpdater
    attr_reader :gemfile, :dependency

    BUMP_TMP_FILE_PREFIX = "bump_".freeze
    BUMP_TMP_DIR_PATH = "tmp".freeze

    def initialize(gemfile:, dependency:)
      @gemfile = gemfile
      @dependency = dependency
    end

    def updated_dependency_files
      return @updated_dependency_files if @updated_dependency_files

      @updated_dependency_files = [
        DependencyFile.new(name: "Gemfile", content: updated_gemfile),
        DependencyFile.new(name: "Gemfile.lock", content: updated_gemfile_lock)
      ]
    end

    private

    def updated_gemfile
      return @updated_gemfile if @updated_gemfile

      lines = gemfile.split("\n")

      lines.each do |line|
        match = line.match(Gemnasium::Parser::Patterns::GEM_CALL)
        next unless match && match[:name] == dependency.name

        line.sub!(/[\d\.]+/, dependency.version)
      end

      @updated_gemfile = lines.join("\n")
    end

    def updated_gemfile_lock
      return @updated_gemfile_lock if @updated_gemfile_lock

      in_a_temporary_directory do |dir|
        File.write(File.join(dir, "Gemfile"), updated_gemfile)
        Bundler.with_clean_env { system "cd #{dir} && bundle install --quiet" }
        @updated_gemfile_lock = File.read(File.join(dir, "Gemfile.lock"))
      end

      @updated_gemfile_lock
    end

    def in_a_temporary_directory
      Dir.mkdir(BUMP_TMP_DIR_PATH) unless Dir.exists?(BUMP_TMP_DIR_PATH)
      Dir.mktmpdir(BUMP_TMP_FILE_PREFIX, BUMP_TMP_DIR_PATH) do |dir|
        yield dir
      end
    end
  end
end
