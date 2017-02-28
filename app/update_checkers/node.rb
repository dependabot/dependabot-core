require "./app/update_checkers/base"
require "json"
require "net/http"

module UpdateCheckers
  class Node < Base
    def latest_version
      @latest_version ||=
        begin
          JSON.parse(Net::HTTP.get(dependency_url))["dist-tags"]["latest"]
        end
    end

    def dependency_version
      Gem::Version.new(dependency.version)
    end

    private

    def dependency_url
      path = dependency.name.gsub("/", "%2F")
      URI("http://registry.npmjs.org/#{path}")
    end

    def language
      "node"
    end
  end
end
