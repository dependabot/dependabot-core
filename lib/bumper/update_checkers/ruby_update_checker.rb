require "json"

module UpdateCheckers
  class RubyUpdateChecker
    attr_reader :dependency, :gemfile_lock

    def initialize(dependency:, dependency_files:)
      @dependency = dependency
      @gemfile_lock = dependency_files.find { |f| f.name == "Gemfile.lock" }
    end

    def needs_update?
      Gem::Version.new(latest_version) > Gem::Version.new(dependency.version)
    end

    def latest_version
      @latest_version ||= Gem.latest_version_for(dependency.name).to_s
    end
  end
end
