# frozen_string_literal: true

require "bundler"
require "bundler/lazy_specification"
require "bundler/shared_helpers"

module Functions
  class SpecParser
    class Position
      attr_reader :line, :column
      def initialize(line, column)
        @line = line
        @column = column
      end

      def advance!(string)
        lines = string.count("\n")
        if lines > 0
          @line += lines
          @column = string.length - string.rindex("\n")
        else
          @column += string.length
        end
      end

      def to_s
        "#{line}:#{column}"
      end
    end

    attr_reader(
      :sources,
      :dependencies,
      :specs,
      :platforms,
      :bundler_version,
      :ruby_version,
      :checksums,
      )

    BUNDLED      = "BUNDLED WITH"
    DEPENDENCIES = "DEPENDENCIES"
    CHECKSUMS    = "CHECKSUMS"
    PLATFORMS    = "PLATFORMS"
    RUBY         = "RUBY VERSION"
    GIT          = "GIT"
    GEM          = "GEM"
    PATH         = "PATH"
    PLUGIN       = "PLUGIN SOURCE"
    SPECS        = "  specs:"
    OPTIONS      = /^  ([a-z]+): (.*)$/i
    SOURCE       = [GIT, GEM, PATH, PLUGIN].freeze

    SECTIONS_BY_VERSION_INTRODUCED = {
      Gem::Version.create("1.0") => [DEPENDENCIES, PLATFORMS, GIT, GEM, PATH].freeze,
      Gem::Version.create("1.10") => [BUNDLED].freeze,
      Gem::Version.create("1.12") => [RUBY].freeze,
      Gem::Version.create("1.13") => [PLUGIN].freeze,
      Gem::Version.create("2.5.0") => [CHECKSUMS].freeze,
    }.freeze

    KNOWN_SECTIONS = SECTIONS_BY_VERSION_INTRODUCED.values.flatten!.freeze

    ENVIRONMENT_VERSION_SECTIONS = [BUNDLED, RUBY].freeze
    deprecate_constant(:ENVIRONMENT_VERSION_SECTIONS)

    def self.sections_in_lockfile(lockfile_contents)
      sections = lockfile_contents.scan(/^\w[\w ]*$/)
      sections.uniq!
      sections
    end

    def self.unknown_sections_in_lockfile(lockfile_contents)
      sections_in_lockfile(lockfile_contents) - KNOWN_SECTIONS
    end

    def self.sections_to_ignore(base_version = nil)
      base_version &&= base_version.release
      base_version ||= Gem::Version.create("1.0")
      attributes = []
      SECTIONS_BY_VERSION_INTRODUCED.each do |version, introduced|
        next if version <= base_version
        attributes += introduced
      end
      attributes
    end

    def self.bundled_with
      lockfile = Bundler.default_lockfile
      return unless lockfile.file?

      lockfile_contents = Bundler.read_file(lockfile)
      return unless lockfile_contents.include?(BUNDLED)

      lockfile_contents.split(BUNDLED).last.strip
    end

    def initialize(lockfile)
      @platforms    = []
      @sources      = []
      @dependencies = {}
      @parse_method = nil
      @specs        = {}
      @lockfile_path = begin
                         Bundler::SharedHelpers.relative_lockfile_path
                       rescue Bundler::GemfileNotFound
                         "Gemfile.lock"
                       end
      @pos = Position.new(1, 1)

      File.foreach(lockfile) do |line|
        # split alternates between the line and the following whitespace
        next @pos.advance!(line) if line.match?(/^\s*$/)

        if SOURCE.include?(line)
          @parse_method = :parse_source
          parse_source(line)
        elsif line == DEPENDENCIES
          @parse_method = :parse_dependency
        elsif line == CHECKSUMS
          # This is a temporary solution to make this feature disabled by default
          # for all gemfiles that don't already explicitly include the feature.
          @checksums = true
          @parse_method = :parse_checksum
        elsif line == PLATFORMS
          @parse_method = :parse_platform
        elsif line == RUBY
          @parse_method = :parse_ruby
        elsif line == BUNDLED
          @parse_method = :parse_bundled_with
        elsif /^[^\s]/.match?(line)
          @parse_method = nil
        elsif @parse_method
          send(@parse_method, line)
        end
        @pos.advance!(line)
      end
      @specs = @specs.values.sort_by!(&:full_name)
    rescue ArgumentError => e
      Bundler.ui.debug(e)
      raise Bundler::LockfileError, "Your lockfile is unreadable. Run `rm #{@lockfile_path}` " \
        "and then `bundle install` to generate a new lockfile. The error occurred while " \
        "evaluating #{@lockfile_path}:#{@pos}"
    end

    def may_include_redundant_platform_specific_gems?
      bundler_version.nil? || bundler_version < Gem::Version.new("1.16.2")
    end

    private

    TYPES = {
      GIT => Bundler::Source::Git,
      GEM => Bundler::Source::Rubygems,
      PATH => Bundler::Source::Path,
      PLUGIN => Bundler::Plugin,
    }.freeze

    def parse_source(line)
      case line
      when SPECS
        return unless TYPES.key?(@type)
        @current_source = TYPES[@type].from_lock(@opts)
        @sources << @current_source
      when OPTIONS
        value = $2
        value = true if value == "true"
        value = false if value == "false"

        key = $1

        if @opts[key]
          @opts[key] = Array(@opts[key])
          @opts[key] << value
        else
          @opts[key] = value
        end
      when *SOURCE
        @current_source = nil
        @opts = {}
        @type = line
      else
        parse_spec(line)
      end
    end

    space = / /
    NAME_VERSION = /
      ^(#{space}{2}|#{space}{4}|#{space}{6})(?!#{space}) # Exactly 2, 4, or 6 spaces at the start of the line
      (.*?)                                              # Name
      (?:#{space}\(([^-]*)                               # Space, followed by version
      (?:-(.*))?\))?                                     # Optional platform
      (!)?                                               # Optional pinned marker
      (?:#{space}([^ ]+))?                               # Optional checksum
      $                                                  # Line end
    /xo

    def parse_dependency(line)
    end

    def parse_checksum(line)
    end

    def parse_spec(line)
      return unless line =~ NAME_VERSION
      spaces = $1
      name = -$2
      version = $3

      if spaces.size == 4
        # only load platform for non-dependency (spec) line
        platform = $4

        version = Gem::Version.new(version)
        platform = platform ? Gem::Platform.new(platform) : Gem::Platform::RUBY
        @current_spec = Bundler::LazySpecification.new(name, version, platform, @current_source)
        @current_source.add_dependency_names(name)

        @specs[@current_spec.full_name] = @current_spec
      elsif spaces.size == 6
        version = version.split(",").each(&:strip!) if version
        dep = Gem::Dependency.new(name, version)
        @current_spec.dependencies << dep
      end
    end

    def parse_platform(line)
    end

    def parse_bundled_with(line)
    end

    def parse_ruby(line)
    end
  end
end
