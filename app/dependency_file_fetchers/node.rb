require "./app/dependency_file_fetchers/base"

module DependencyFileFetchers
  class Node < Base
    def files
      @files ||= [
        fetch_file_from_github("package.json"),
        fetch_file_from_github("yarn.lock")
      ]
    end
  end
end
