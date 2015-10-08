require "json"

module UpdateCheckers
  class RubyUpdateChecker
    attr_reader :dependency, :gemfile, :gemfile_lock

    def initialize(dependency:, dependency_files:)
      @dependency = dependency
      @gemfile = dependency_files.find { |f| f.name == "Gemfile" }
      @gemfile_lock = dependency_files.find { |f| f.name == "Gemfile.lock" }
      validate_files_are_present!
    end

    def needs_update?
      Gem::Version.new(latest_version) > dependency_version
    end

    def latest_version
      @latest_version ||= Gems.info(dependency.name)["version"]
    end

    private

    def validate_files_are_present!
      raise "No Gemfile!" unless gemfile
      raise "No Gemfile.lock!" unless gemfile_lock
    end

    # Parse the Gemfile.lock to get the gem version. Better than just relying
    # on the dependency's specified version, which may have had a ~> matcher.
    def dependency_version
      parsed_lockfile = Bundler::LockfileParser.new(gemfile_lock.content)
      parsed_lockfile.specs.find { |spec| spec.name == dependency.name }.version
    end
  end
end
