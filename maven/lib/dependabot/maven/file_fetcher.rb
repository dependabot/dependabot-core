# typed: strict
# frozen_string_literal: true

require "base64"
require "nokogiri"
require "sorbet-runtime"

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/file_filtering"
require "dependabot/experiments"
require "dependabot/maven/file_parser/wrapper_mojo"

module Dependabot
  module Maven
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      MODULE_SELECTOR = "project > modules > module, " \
                        "profile > modules > module"

      WRAPPER_PROPERTIES_RELATIVE = ".mvn/wrapper/maven-wrapper.properties"
      WRAPPER_JAR_RELATIVE        = ".mvn/wrapper/maven-wrapper.jar"
      WRAPPER_DOWNLOADER_RELATIVE = ".mvn/wrapper/MavenWrapperDownloader.java"

      WRAPPER_UNIX_SCRIPTS    = %w(mvnw mvnwDebug).freeze
      WRAPPER_WINDOWS_SCRIPTS = %w(mvnw.cmd mvnwDebug.cmd).freeze
      WRAPPER_ALL_SCRIPTS     = T.let((WRAPPER_UNIX_SCRIPTS + WRAPPER_WINDOWS_SCRIPTS).freeze, T::Array[String])

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?("pom.xml")
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a pom.xml."
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = []
        fetched_files << pom
        poms = child_poms
        fetched_files += poms
        fetched_files += relative_path_parents(fetched_files)
        fetched_files += targetfiles
        fetched_files << extensions if extensions
        # Pass already-fetched poms so all_wrapper_files does not re-fetch them.
        fetched_files += all_wrapper_files([T.must(pom)] + poms)

        # Filter excluded files from final collection
        filtered_files = fetched_files.uniq.reject do |file|
          Dependabot::FileFiltering.should_exclude_path?(file.name, "file from final collection", @exclude_paths)
        end

        filtered_files
      end

      private

      sig { params(dir: String).returns(T::Array[DependencyFile]) }
      def wrapper_files_for_dir(dir)
        return [] unless Dependabot::Experiments.enabled?(:maven_wrapper_updater)

        # Strip leading "./" from root-level paths
        properties_path = File.join(dir, WRAPPER_PROPERTIES_RELATIVE).delete_prefix("./")
        properties = fetch_file_if_present(properties_path)
        return [] unless properties

        files = T.let([properties], T::Array[DependencyFile])
        WRAPPER_ALL_SCRIPTS.each do |script|
          script_path = dir == "." ? script : File.join(dir, script)
          f = fetch_file_if_present(script_path)
          files << f if f
        end

        dist_type = FileParser::WrapperMojo.resolve_distribution_type(T.must(properties.content))
        files + fetch_wrapper_artifact_files(dir, dist_type)
      rescue Dependabot::DependencyFileNotFound
        []
      end

      sig { params(dir: String, dist_type: String).returns(T::Array[DependencyFile]) }
      def fetch_wrapper_artifact_files(dir, dist_type)
        case dist_type
        when "bin", "script"
          jar_path = File.join(dir, WRAPPER_JAR_RELATIVE).delete_prefix("./")
          jar = fetch_file_if_present(jar_path)
          return [] unless jar

          jar.content = Base64.encode64(T.must(jar.content)) if jar.content
          jar.content_encoding = DependencyFile::ContentEncoding::BASE64
          [jar]
        when "source"
          dl_path = File.join(dir, WRAPPER_DOWNLOADER_RELATIVE).delete_prefix("./")
          downloader = fetch_file_if_present(dl_path)
          downloader ? [downloader] : []
        else
          []
        end
      end

      sig { params(poms: T::Array[DependencyFile]).returns(T::Array[DependencyFile]) }
      def all_wrapper_files(poms)
        seen_dirs = T.let(Set.new, T::Set[String])
        poms.filter_map do |pom_file|
          dir = File.dirname(pom_file.name)
          next if seen_dirs.include?(dir)

          seen_dirs << dir
          wrapper_files_for_dir(dir)
        end.flatten
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pom
        @pom ||= T.let(fetch_file_from_host("pom.xml"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def extensions
        @extensions ||= T.let(fetch_file_if_present(".mvn/extensions.xml"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T::Array[DependencyFile]) }
      def targetfiles
        repo_contents(raise_errors: false)
          .select { |f| f.type == "file" && f.name.end_with?(".target") }
          .map { |f| fetch_file_from_host(f.name) }
      rescue Dependabot::DirectoryNotFound, Octokit::NotFound
        []
      end

      sig { returns(T::Array[DependencyFile]) }
      def child_poms
        recursively_fetch_child_poms(T.must(pom), fetched_filenames: ["pom.xml"])
      end

      sig { params(fetched_files: T::Array[Dependabot::DependencyFile]).returns(T::Array[Dependabot::DependencyFile]) }
      def relative_path_parents(fetched_files)
        fetched_files.flat_map do |file|
          recursively_fetch_relative_path_parents(
            file,
            fetched_filenames: fetched_files.map(&:name)
          )
        end
      end

      sig do
        params(
          pom: Dependabot::DependencyFile,
          fetched_filenames: T::Array[String]
        ).returns(T::Array[Dependabot::DependencyFile])
      end
      def recursively_fetch_child_poms(pom, fetched_filenames:)
        base_path = File.dirname(pom.name)
        doc = Nokogiri::XML(pom.content)

        doc.css(MODULE_SELECTOR).flat_map do |module_node|
          relative_path = module_node.content.strip
          name_parts = [
            base_path,
            relative_path,
            relative_path.end_with?(".xml") ? nil : "pom.xml"
          ].compact.reject(&:empty?)
          path = Pathname.new(File.join(name_parts)).cleanpath.to_path

          next [] if fetched_filenames.include?(path)

          next [] if Dependabot::FileFiltering.should_exclude_path?(path, "file from final collection", @exclude_paths)

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
          fetch_file_from_host(T.must(path), fetch_submodules: true)

          [] # Ignore any child submodules (since we can't update them)
        end
      end

      sig do
        params(
          pom: Dependabot::DependencyFile,
          fetched_filenames: T::Array[String]
        ).returns(T::Array[Dependabot::DependencyFile])
      end
      def recursively_fetch_relative_path_parents(pom, fetched_filenames:)
        path = parent_path_for_pom(pom)

        return [] if path.nil? || fetched_filenames.include?(path)

        full_path_parts =
          [directory.gsub(%r{^/}, ""), path].reject(&:empty?).compact

        full_path = Pathname.new(File.join(full_path_parts)).cleanpath.to_path

        return [] if full_path.start_with?("..")

        parent_pom = fetch_file_from_host(path)

        return [] unless fetched_pom_is_parent(pom, parent_pom)

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

      sig { params(pom: Dependabot::DependencyFile).returns(T.nilable(String)) }
      def parent_path_for_pom(pom)
        doc = Nokogiri::XML(pom.content)
        doc.remove_namespaces!

        return unless doc.at_xpath("/project/parent")

        relative_parent_path =
          doc.at_xpath("/project/parent/relativePath")&.content&.strip || ".."

        name_parts = [
          File.dirname(pom.name),
          relative_parent_path,
          relative_parent_path.end_with?(".xml") ? nil : "pom.xml"
        ].compact.reject(&:empty?)

        Pathname.new(File.join(name_parts)).cleanpath.to_path
      end

      sig { params(pom: Dependabot::DependencyFile, parent_pom: Dependabot::DependencyFile).returns(T::Boolean) }
      def fetched_pom_is_parent(pom, parent_pom)
        pom_doc = Nokogiri::XML(pom.content).remove_namespaces!
        pom_artifact_id, pom_group_id, pom_version = fetch_pom_unique_ids(pom_doc, true)

        parent_doc = Nokogiri::XML(parent_pom.content).remove_namespaces!
        parent_artifact_id, parent_group_id, parent_version = fetch_pom_unique_ids(parent_doc, false)

        if parent_group_id.nil?
          [parent_artifact_id, parent_version] == [pom_artifact_id, pom_version]
        else
          [parent_group_id, parent_artifact_id, parent_version] == [pom_group_id, pom_artifact_id, pom_version]
        end
      end

      sig { params(doc: Nokogiri::XML::Document, check_parent_node: T::Boolean).returns(T::Array[T.nilable(String)]) }
      def fetch_pom_unique_ids(doc, check_parent_node)
        parent = check_parent_node ? "/parent" : ""
        group_id = doc.at_xpath("/project#{parent}/groupId")&.content&.strip
        artifact_id = doc.at_xpath("/project#{parent}/artifactId")&.content&.strip
        version = doc.at_xpath("/project#{parent}/version")&.content&.strip
        [artifact_id, group_id, version]
      end
    end
  end
end

Dependabot::FileFetchers.register("maven", Dependabot::Maven::FileFetcher)
