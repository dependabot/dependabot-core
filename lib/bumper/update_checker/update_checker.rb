# require "gem/version"
require "net/http"
require "json"

module UpdateChecker

  # checks for dependencies that are out of date
  #
  # usage:
  #     UpdateChecker::RubyUpdateChecker.new(initial_dependencies).run
  #
  # dependencies, Array
  # return an Array of dependencies that are out of date
  class RubyUpdateChecker
    def initialize(dependencies)
      @dependencies = dependencies
    end

    def run
      @dependencies.select do |dependency|
        latest_version = get_latest(dependency)["version"]
        Gem::Version.new(latest_version) > Gem::Version.new(dependency.version)
      end
    end

    private

    def get_latest(dependency)
      JSON.parse(Net::HTTP.get(URI("https://rubygems.org/api/v1/gems/#{dependency.name}.json")))
    end
  end
end
