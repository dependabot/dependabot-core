# frozen_string_literal: true

module ProjectFixtures
  class Builder
    attr_reader :data

    BASE_FOLDER = "spec/fixtures/projects/"

    def initialize(data)
      @data = data
    end

    def run
      project_dir = FileUtils.mkdir_p(File.join(BASE_FOLDER, subfolder, data.project_name)).last
      Dir.chdir(project_dir) do
        data.files.each do |file|
          if file.directory == "/"
            File.write(file.name, file.content)
          else
            subdir = FileUtils.mkdir(file.directory).last
            Dir.chdir(subdir) { File.write(file.name, file.content) }
          end
        end
      end

      File.join(subfolder, data.project_name)
    end

    def subfolder
      "bundler1"
    end
  end
end
