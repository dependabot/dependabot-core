# frozen_string_literal: true

require "nokogiri"
require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Java
      class Maven < Dependabot::FileFetchers::Base
        MODULE_SELECTOR = "project > modules > module"

        def self.required_files_in?(filenames)
          (%w(pom.xml) - filenames).empty?
        end

        def self.required_files_message
          "Repo must contain a pom.xml."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << pom
          fetched_files += child_poms
          fetched_files
        end

        def pom
          @pom ||= fetch_file_from_host("pom.xml")
        end

        def child_poms
          recursively_fetch_child_poms(pom, fetched_filenames: ["pom.xml"])
        end

        def recursively_fetch_child_poms(pom, fetched_filenames:)
          base_path = pom.name.gsub(/pom\.xml$/, "")
          doc = Nokogiri::XML(pom.content)

          doc.css(MODULE_SELECTOR).flat_map do |module_node|
            relative_path = module_node.content.strip
            name_parts = [
              base_path,
              relative_path,
              relative_path.end_with?("pom.xml") ? nil : "pom.xml"
            ].compact.reject(&:empty?)
            path = Pathname.new(File.join(*name_parts)).cleanpath.to_path

            next [] if fetched_filenames.include?(path)

            child_pom = fetch_file_from_host(File.join(*name_parts))
            fetched_filenames += [child_pom.name]
            [
              child_pom,
              recursively_fetch_child_poms(
                child_pom,
                fetched_filenames: fetched_filenames
              )
            ].flatten
          end
        end
      end
    end
  end
end
