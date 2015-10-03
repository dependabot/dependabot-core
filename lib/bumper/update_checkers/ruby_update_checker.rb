require "json"

module UpdateCheckers

  # checks for dependencies that are out of date
  #
  # usage:
  #     UpdateChecker::RubyUpdateChecker.new(initial_dependencies).outdated_dependencies
  #
  # dependencies, Array
  # return an Array of dependencies that are out of date
  class RubyUpdateChecker
    attr_reader :dependencies

    BASE_URL = "https://rubygems.org/api/v1".freeze

    def initialize(dependencies)
      @dependencies = dependencies
    end

    def outdated_dependencies
      dependencies.select do |dependency|
        latest_version = rubygems_info_for(dependency)["version"]
        Gem::Version.new(latest_version) > Gem::Version.new(dependency.version)
      end
    end

    private

    def rubygems_info_for(dependency)
      rubygems_response = Net::HTTP.get(URI.parse(rubygems_url(dependency)))
      JSON.parse(rubygems_response)
    end

    def rubygems_url(dependency)
      "#{BASE_URL}/gems/#{dependency.name}.json"
    end
  end
end
