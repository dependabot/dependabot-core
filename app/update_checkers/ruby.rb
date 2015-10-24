require "./app/update_checkers/base"

module UpdateCheckers
  class Ruby < Base
    def latest_version
      @latest_version ||= Gems.info(dependency.name)["version"]
    end

    # Parse the Gemfile.lock to get the gem version. Better than just relying
    # on the dependency's specified version, which may have had a ~> matcher.
    def dependency_version
      parsed_lockfile = Bundler::LockfileParser.new(gemfile_lock.content)

      return Gem::Version.new(Bundler::VERSION) if dependency.name == "bundler"
      parsed_lockfile.specs.find { |spec| spec.name == dependency.name }.version
    end

    private

    def gemfile_lock
      lockfile = dependency_files.find { |f| f.name == "Gemfile.lock" }
      raise "No Gemfile.lock!" unless lockfile
      lockfile
    end
  end
end
