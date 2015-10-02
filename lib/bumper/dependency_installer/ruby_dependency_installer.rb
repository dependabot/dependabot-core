require "gemnasium/parser"
require "bumper/dependency_file"
require "tmpdir"
require "bundler"

module DependencyInstaller
  # NOTE: in ruby a requirement is a matcher and version
  # e.g. "~> 1.2.3", where "~>" is the match
  class RubyDependencyInstaller

    attr_reader :gemfile, :dependency, :updated_dependency_files

    BUMP_TMP_FILE_PREFIX = "bump_".freeze
    BUMP_TMP_DIR_PATH = "tmp".freeze

    def initialize(gemfile, dependency)
      @gemfile = gemfile
      @dependency = dependency
    end

    def install
      @updated_dependency_files = []

      Dir.mkdir(BUMP_TMP_DIR_PATH) unless Dir.exists?(BUMP_TMP_DIR_PATH)
      # providing a block to mktmpdir triggers an auto-delete on the tmp dir
      Dir.mktmpdir(BUMP_TMP_FILE_PREFIX, BUMP_TMP_DIR_PATH) do |dir|
        new_gemfile = update_gem_file
        updated_dependency_files << DependencyFile.new(name: "Gemfile", content: new_gemfile.to_s)
        File.write(File.join(dir, "Gemfile"), new_gemfile)

        Bundler.with_clean_env { system "cd #{dir} && bundle install --quiet" }
        updated_dependency_files << DependencyFile.new(name: "Gemfile.lock", content: File.read(File.join(dir, "Gemfile.lock")).to_s)
      end

      updated_dependency_files
    end

    private

    def update_gem_file
      # m = gemfile.match(Gemnasium::Parser::Patterns::GEM_CALL)
      # m.offset(5) # 5th part is the requirement
      # new_gemfile = gemfile.dup
      # new_gemfile[45...53].match(/[\d\.]+/).offset(0)
      # new_gemfile[0...(45+3)] + dependency.version + new_gemfile[(45+8)...-1]
      # new_gemfile
      gemfile
    end
  end
end
