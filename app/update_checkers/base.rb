require "json"

module UpdateCheckers
  class Base
    attr_reader :dependency, :dependency_files

    def initialize(dependency:, dependency_files:)
      @dependency = dependency
      @dependency_files = dependency_files
    end

    def needs_update?
      Gem::Version.new(latest_version) > dependency_version
    end

    def latest_version
      raise NotImplementedError
    end
  end
end
