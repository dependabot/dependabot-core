# typed: strict
# frozen_string_literal: true

require "nokogiri"
require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/maven/file_parser"

module Dependabot
  module Maven
    class FileParser
      # Decides whether a `<dependencyManagement>` entry overrides a transitive version.
      #
      # An entry is an override when no POM in its local lineage (itself, its local
      # parents and its local children) declares the artifact in a `<dependencies>`
      # section. Parents count because their dependencies are inherited; sibling
      # modules don't, as the entry doesn't manage their declarations. A local BOM,
      # and every local POM inheriting from it, also manages the lineage of each
      # local POM that imports it.
      class TransitiveOverrideFinder
        extend T::Sig

        sig do
          params(
            pomfiles: T::Array[Dependabot::DependencyFile],
            declared_keys_by_pom: T::Hash[String, T::Set[String]],
            property_value_finder: PropertyValueFinder
          ).void
        end
        def initialize(pomfiles:, declared_keys_by_pom:, property_value_finder:)
          @pomfiles = pomfiles
          @declared_keys_by_pom = declared_keys_by_pom
          @property_value_finder = property_value_finder
          @lineages = T.let({}, T::Hash[String, T::Array[String]])
          @documents = T.let({}, T::Hash[String, Nokogiri::XML::Document])
        end

        # `key` is the entry's groupId:artifactId:type:classifier management key.
        sig { params(pom: Dependabot::DependencyFile, key: String).returns(T::Boolean) }
        def override?(pom:, key:)
          lineage(pom.name).none? { |pom_name| @declared_keys_by_pom.fetch(pom_name, Set.new).include?(key) }
        end

        private

        sig { params(pom_name: String).returns(T::Array[String]) }
        def lineage(pom_name)
          @lineages[pom_name] ||= begin
            found = T.let([], T::Array[String])
            visited = T.let([], T::Array[String])
            queue = [pom_name]
            while (current = queue.shift)
              next if visited.include?(current)

              visited << current
              found.concat(inheritance_line(current)).uniq!
              # Importing a BOM also imports what it inherits, so importers of its children count too.
              ([current] + descendants(current)).each do |bom|
                queue.concat(local_importer_names.fetch(bom, []))
              end
            end
            found
          end
        end

        sig { params(pom_name: String).returns(T::Array[String]) }
        def inheritance_line(pom_name)
          ancestors(pom_name) + [pom_name] + descendants(pom_name)
        end

        # Maps each local BOM file name to the file names of the local POMs that import it.
        sig { returns(T::Hash[String, T::Array[String]]) }
        def local_importer_names
          @local_importer_names ||= T.let(
            @pomfiles.each_with_object({}) do |pom, importers|
              imported_coordinates(pom).each do |coordinates|
                bom = coordinates_to_pom_name[coordinates]
                next if bom.nil? || bom == pom.name

                (importers[bom] ||= []) << pom.name
              end
            end,
            T.nilable(T::Hash[String, T::Array[String]])
          )
        end

        sig { params(pom: Dependabot::DependencyFile).returns(T::Array[String]) }
        def imported_coordinates(pom)
          document(pom).xpath("//dependencyManagement/dependencies/dependency").filter_map do |node|
            import_coordinates(node, pom)
          end
        end

        sig { params(node: Nokogiri::XML::Element, pom: Dependabot::DependencyFile).returns(T.nilable(String)) }
        def import_coordinates(node, pom)
          return unless child_value(node, "scope", pom) == "import"

          group_id = child_value(node, "groupId", pom)
          artifact_id = child_value(node, "artifactId", pom)
          return unless group_id && artifact_id

          "#{group_id}:#{artifact_id}"
        end

        sig do
          params(node: Nokogiri::XML::Element, name: String, pom: Dependabot::DependencyFile).returns(T.nilable(String))
        end
        def child_value(node, name, pom)
          resolved_text(node.at_xpath("./#{name}"), pom)
        end

        sig { params(node: T.nilable(Nokogiri::XML::Node), pom: Dependabot::DependencyFile).returns(T.nilable(String)) }
        def resolved_text(node, pom)
          value = T.let(node&.content&.strip, T.nilable(String))
          return value unless value&.match?(PROPERTY_REGEX)

          value.gsub(PROPERTY_REGEX) do |placeholder|
            resolved_property(T.must(Regexp.last_match)[:property].to_s, pom) || placeholder
          end
        end

        sig { params(property_name: String, pom: Dependabot::DependencyFile).returns(T.nilable(String)) }
        def resolved_property(property_name, pom)
          details = @property_value_finder.property_details(property_name: property_name, callsite_pom: pom)
          value = details&.fetch(:value)
          value.is_a?(String) ? value : nil
        rescue Dependabot::DependabotError
          nil
        end

        sig { params(pom_name: String).returns(T::Array[String]) }
        def ancestors(pom_name)
          found = T.let([], T::Array[String])
          current = T.let(local_parent_names[pom_name], T.nilable(String))
          while current && !found.include?(current) && current != pom_name
            found << current
            current = local_parent_names[current]
          end
          found
        end

        sig { params(pom_name: String).returns(T::Array[String]) }
        def descendants(pom_name)
          found = T.let([], T::Array[String])
          queue = [pom_name]
          while (current = queue.shift)
            local_parent_names.each do |child, parent|
              next unless parent == current
              next if child == pom_name || found.include?(child)

              found << child
              queue << child
            end
          end
          found
        end

        # Maps each POM file name to the file name of its parent, when the parent is in the job.
        sig { returns(T::Hash[String, String]) }
        def local_parent_names
          @local_parent_names ||= T.let(
            @pomfiles.each_with_object({}) do |pom, parents|
              coordinates = parent_coordinates(pom)
              parent = coordinates && coordinates_to_pom_name[coordinates]
              parents[pom.name] = parent if parent && parent != pom.name
            end,
            T.nilable(T::Hash[String, String])
          )
        end

        sig { returns(T::Hash[String, String]) }
        def coordinates_to_pom_name
          @coordinates_to_pom_name ||= T.let(
            @pomfiles.each_with_object({}) do |pom, map|
              doc = document(pom)
              group_id = resolved_text(doc.at_xpath("/project/groupId") || doc.at_xpath("/project/parent/groupId"), pom)
              artifact_id = resolved_text(doc.at_xpath("/project/artifactId"), pom)
              next unless group_id && artifact_id

              map["#{group_id}:#{artifact_id}"] ||= pom.name
            end,
            T.nilable(T::Hash[String, String])
          )
        end

        sig { params(pom: Dependabot::DependencyFile).returns(T.nilable(String)) }
        def parent_coordinates(pom)
          doc = document(pom)
          group_id = doc.at_xpath("/project/parent/groupId")
          artifact_id = doc.at_xpath("/project/parent/artifactId")
          return unless group_id && artifact_id

          "#{group_id.content.strip}:#{artifact_id.content.strip}"
        end

        sig { params(pom: Dependabot::DependencyFile).returns(Nokogiri::XML::Document) }
        def document(pom)
          @documents[pom.name] ||= begin
            doc = Nokogiri::XML(pom.content)
            doc.remove_namespaces!
            doc
          end
        end
      end
    end
  end
end
