require "./app/update_checkers/base"
require "open-uri"

module UpdateCheckers
  class Python < Base
    def latest_version
      @latest_version ||=
        begin
          url = URI("https://pypi.python.org/pypi/#{dependency.name}/json")
          JSON.parse(open(url).read)["info"]["version"]
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
