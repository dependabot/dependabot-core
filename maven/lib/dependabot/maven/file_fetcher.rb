# frozen_string_literal: true

require "nokogiri"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Maven
    class FileFetcher < Dependabot::FileFetchers::Base
      MODULE_SELECTOR = "project > modules > module, " \
                        "profile > modules > module"

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
        fetched_files += relative_path_parents(fetched_files)
        fetched_files << extensions if extensions
        fetched_files.uniq
      end

      def pom
        @pom ||= fetch_file_from_host("pom.xml")
      end

      def extensions
        return @extensions if defined?(@extensions)
        return @extensions if defined?(@extensions)

        begin
          fetch_file_if_present(".mvn/extensions.xml")
        rescue Dependabot::DependencyFileNotFound
          nil
        end
      end

      def child_poms
        recursively_fetch_child_poms(pom, fetched_filenames: ["pom.xml"])
      end

      def relative_path_parents(fetched_files)
        fetched_files.flat_map do |file|
          recursively_fetch_relative_path_parents(
            file,
            fetched_filenames: fetched_files.map(&:name)
          )
        end
      end

      def recursively_fetch_child_poms(pom, fetched_filenames:)
        base_path = File.dirname(pom.name)
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

          child_pom = fetch_file_from_host(path)
          fetched_files = [
            child_pom,
            recursively_fetch_child_poms(
              child_pom,
              fetched_filenames: fetched_filenames + [child_pom.name]
            )
          ].flatten
          fetched_filenames += [child_pom.name] + fetched_files.map(&:name)
          fetched_files
        rescue Dependabot::DependencyFileNotFound
          raise unless fetch_file_from_host(path, fetch_submodules: true)

          [] # Ignore any child submodules (since we can't update them)
        end
      end

      def recursively_fetch_relative_path_parents(pom, fetched_filenames:)
        path = parent_path_for_pom(pom)

        return [] if fetched_filenames.include?(path)

        full_path_parts =
          [directory.gsub(%r{^/}, ""), path].reject(&:empty?).compact

        full_path = Pathname.new(File.join(*full_path_parts)).
                    cleanpath.to_path

        return [] if full_path.start_with?("..")

        parent_pom = fetch_file_from_host(path)
        parent_pom.support_file = true

        [
          parent_pom,
          recursively_fetch_relative_path_parents(
            parent_pom,
            fetched_filenames: fetched_filenames + [parent_pom.name]
          )
        ].flatten
      rescue Dependabot::DependencyFileNotFound
        []
      end

      def parent_path_for_pom(pom)
        doc = Nokogiri::XML(pom.content)
        doc.remove_namespaces!

        relative_parent_path =
          doc.at_xpath("/project/parent/relativePath")&.content&.strip || ".."

        name_parts = [
          File.dirname(pom.name),
          relative_parent_path,
          relative_parent_path.end_with?("pom.xml", "pom_parent.xml") ? nil : "pom.xml"
        ].compact.reject(&:empty?)

        Pathname.new(File.join(*name_parts)).cleanpath.to_path
      end
    end
  end
end

Dependabot::FileFetchers.register("maven", Dependabot::Maven::FileFetcher)
