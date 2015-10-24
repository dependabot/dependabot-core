require "json"
require "net/http"

module UpdateCheckers
  class Node
    attr_reader :dependency

    def initialize(dependency:, dependency_files:)
      @dependency = dependency
    end

    def needs_update?
      Gem::Version.new(latest_version.match(/[\d\.]+/)) > Gem::Version.new(dependency.version.match(/[\d\.]+/))
    end

    def latest_version
      url = URI("http://registry.npmjs.org/#{dependency.name}")
      @latest_version ||=
        JSON.parse(Net::HTTP.get(url))["dist-tags"]["latest"]
    end
  end
end
