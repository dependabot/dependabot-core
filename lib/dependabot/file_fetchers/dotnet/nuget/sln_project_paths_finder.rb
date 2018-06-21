# frozen_string_literal: true

require "pathname"
require "dependabot/file_fetchers/dotnet/nuget"

module Dependabot
  module FileFetchers
    module Dotnet
      class Nuget
        class SlnProjectPathsFinder
          PROJECT_PATH_REGEX = /(?<=["'])[^"']*?\.(?:vb|cs|fs)proj(?=["'])/

          def initialize(sln_file:)
            @sln_file = sln_file
          end

          def project_paths
            sln_file.content.scan(PROJECT_PATH_REGEX).map do |path|
              path = path.tr("\\", "/")
              path = File.join(current_dir, path) unless current_dir.nil?
              Pathname.new(path).cleanpath.to_path
            end
          end

          private

          attr_reader :sln_file

          def current_dir
            @current_dir ||= sln_file.name.split("/")[0..-2].last
          end
        end
      end
    end
  end
end
