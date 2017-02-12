require "./app/dependency_file_fetchers/base"

module DependencyFileFetchers
  class Python < Base
    def files
      @files ||= [
        fetch_file_from_github("requirements.txt")
      ]
    end
  end
end
