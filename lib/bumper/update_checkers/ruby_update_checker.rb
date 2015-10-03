require "json"

module UpdateCheckers
  class RubyUpdateChecker
    attr_reader :dependency

    BASE_URL = "https://rubygems.org/api/v1".freeze

    def initialize(dependency)
      @dependency = dependency
    end

    def needs_update?
      Gem::Version.new(latest_version) > Gem::Version.new(dependency.version)
    end

    def latest_version
      @latest_version ||=
        begin
          rubygems_response = Net::HTTP.get(URI.parse(rubygems_url(dependency)))
          JSON.parse(rubygems_response)["version"]
        end
    end

    private

    def rubygems_url(dependency)
      "#{BASE_URL}/gems/#{dependency.name}.json"
    end
  end
end
