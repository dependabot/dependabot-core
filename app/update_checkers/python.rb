# frozen_string_literal: true
require "./app/update_checkers/base"
require "excon"

module UpdateCheckers
  class Python < Base
    def latest_version
      @latest_version ||=
        begin
          url = "https://pypi.python.org/pypi/#{dependency.name}/json"
          JSON.parse(Excon.get(url).body)["info"]["version"]
        end
    end

    def dependency_version
      Gem::Version.new(dependency.version)
    end

    def language
      "python"
    end
  end
end
