require "json"

module UpdateCheckers
  class RubyUpdateChecker
    attr_reader :dependency

    def initialize(dependency:)
      @dependency = dependency
    end

    def needs_update?
      Gem::Version.new(latest_version) > Gem::Version.new(dependency.version)
    end

    def latest_version
      @latest_version ||= Gem.latest_version_for(dependency.name).to_s
    end
  end
end
