# typed: strict
# frozen_string_literal: true

require "nokogiri"
require "pathname"
require "sorbet-runtime"

require "dependabot/nuget/file_fetcher"

module Dependabot
  module Nuget
    class FileFetcher
      class ImportPathsFinder
        extend T::Sig
        sig { params(project_file: T.untyped).void }
        def initialize(project_file:)
          @project_file = T.let(project_file, Dependabot::DependencyFile)
        end

        sig { returns(T::Array[String]) }
        def import_paths
          doc = T.let(Nokogiri::XML(project_file.content), Nokogiri::XML::Document)
          doc.remove_namespaces!
          doc.xpath("/Project/Import").filter_map do |import_node|
            path = import_node.attribute("Project").value.strip.tr("\\", "/")
            path = File.join(current_dir, path) unless current_dir.nil?
            Pathname.new(path).cleanpath.to_path
          end
        end

        sig { returns(T::Array[String]) }
        def project_reference_paths
          doc = T.let(Nokogiri::XML(project_file.content), Nokogiri::XML::Document)
          doc.remove_namespaces!
          doc.xpath("/Project/ItemGroup/ProjectReference").filter_map do |node|
            attribute = node.attribute("Include")
            next unless attribute

            path = attribute.value.strip.tr("\\", "/")
            path = File.join(current_dir, path) unless current_dir.nil?
            Pathname.new(path).cleanpath.to_path
          end
        end

        sig { returns(T::Array[String]) }
        def project_file_paths
          doc = T.let(Nokogiri::XML(project_file.content), Nokogiri::XML::Document)
          doc.remove_namespaces!
          doc.xpath("/Project/ItemGroup/ProjectFile").filter_map do |node|
            attribute = node.attribute("Include")
            next unless attribute

            path = attribute.value.strip.tr("\\", "/")
            path = File.join(current_dir, path) unless current_dir.nil?
            Pathname.new(path).cleanpath.to_path
          end
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :project_file

        sig { returns(T.nilable(String)) }
        def current_dir
          current_dir = project_file.name.rpartition("/").first
          current_dir = nil if current_dir == ""
          current_dir
        end
      end
    end
  end
end
