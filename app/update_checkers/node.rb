require "./app/update_checkers/base"
require "json"
require "net/http"

module UpdateCheckers
  class Node < Base
    def latest_version
      @latest_version ||=
        begin
          url = URI("http://registry.npmjs.org/#{dependency.name}")
          JSON.parse(Net::HTTP.get(url))["dist-tags"]["latest"]
        end
    end

    def dependency_version
      Gem::Version.new(dependency.version)
    end
  end
end
