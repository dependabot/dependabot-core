# typed: strict
# frozen_string_literal: true

require "yaml"
require "dependabot/shared/shared_file_parser"
require "dependabot/helm/package_manager"

module Dependabot
  module Helm
    class FileParser < Dependabot::Shared::SharedFileParser
      extend T::Sig

      CHART_YAML = /.*chart\.ya?ml$/i
      CHART_LOCK = /.*chart\.lock$/i
      VALUES_YAML = /.*values\.ya?ml$/i
      DEFAULT_REPOSITORY = "https://charts.helm.sh/stable"

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: HelmPackageManager.new
          ),
          T.nilable(Ecosystem)
        )
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new
        parse_chart_yaml_files(dependency_set)
        parse_values_yaml_files(dependency_set)

        dependency_set.dependencies
      end

      private

      sig do
        params(
          yaml: T::Hash[T.untyped, T.untyped],
          chart_file: Dependabot::DependencyFile,
          dependency_set: DependencySet
        ).void
      end
      def parse_dependencies(yaml, chart_file, dependency_set)
        yaml["dependencies"].each do |dep|
          next unless dep.is_a?(Hash) && dep["name"] && dep["version"]

          parsed_line = {
            "image" => dep["name"],
            "tag" => dep["version"].to_s,
            "registry" => repository_from_registry(dep["repository"]),
            "digest" => nil
          }

          dependency = build_dependency(chart_file, parsed_line, dep["version"].to_s)
          add_dependency_type_to_dependency(dependency, :helm_chart)

          dependency_set << dependency
        end
      end

      sig { params(dependency: Dependabot::Dependency, type: Symbol).void }
      def add_dependency_type_to_dependency(dependency, type)
        dependency.requirements.map! do |req|
          req[:metadata] = {} unless req[:metadata]
          req[:metadata][:type] = type
          req
        end
      end

      sig { params(repository: T.nilable(String)).returns(String) }
      def repository_from_registry(repository)
        return DEFAULT_REPOSITORY if repository.nil?

        repository
      end

      sig { params(dependency_set: DependencySet).void }
      def parse_chart_yaml_files(dependency_set)
        helm_chart_files.each do |chart_file|
          yaml = YAML.safe_load(T.must(chart_file.content), aliases: true, permitted_classes: [Date, Time, Symbol])
          next unless yaml.is_a?(Hash)

          parse_dependencies(yaml, chart_file, dependency_set) if yaml["dependencies"].is_a?(Array)
        end
      end

      sig { params(dependency_set: DependencySet).void }
      def parse_values_yaml_files(dependency_set)
        helm_values_files.each do |values_file|
          yaml = YAML.safe_load(T.must(values_file.content), aliases: true, permitted_classes: [Date, Time, Symbol])
          next unless yaml.is_a?(Hash)

          find_images_in_hash(yaml).each do |image_details|
            parsed_line = extract_image_details(image_details[:image])
            next unless parsed_line

            version = version_from(parsed_line)
            next unless version

            dependency = build_dependency(values_file, parsed_line, version)
            add_dependency_type_to_dependency(dependency, :docker_image)

            dependency_set << dependency
          end
        end
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { params(image_string: String).returns(T.nilable(T::Hash[String, T.nilable(String)])) }
      def extract_image_details(image_string)
        return nil if image_string.match?(/\${[^}]+}/)

        # Extract components step-by-step to avoid regex backtracking issues
        remaining = image_string.dup

        # Extract digest if present
        digest = nil
        if remaining.include?("@")
          digest_match = remaining.match(/@(?<digest>[^\s]+)$/)
          if digest_match
            digest = digest_match[:digest]
            remaining = remaining.sub(/@#{Regexp.escape(digest)}$/, "") if digest
          end
        end

        # Extract tag if present
        tag = nil
        if remaining.include?(":")
          tag_match = remaining.match(/:(?<tag>[\w][\w.-]{0,127})$/)
          if tag_match
            tag = tag_match[:tag]
            remaining = remaining.sub(/:#{Regexp.escape(tag)}$/, "") if tag
          end
        end

        # Extract registry and image
        # Registry has format: domain.com or domain.com:port
        # Image has format: name or namespace/name or namespace/subnamespace/name
        registry_pattern = %r{
          ^(?<registry>
            [a-z\d](?:[a-z\d]|[._-])*[a-z\d]                # First domain component
            (?:\.[a-z\d](?:[a-z\d]|[._-])*[a-z\d])+         # Additional domain components
            (?::\d+)?                                        # Optional port
          )/
        }ix

        if remaining.match?(registry_pattern)
          # Has registry prefix
          registry_match = remaining.match(registry_pattern)
          if registry_match
            registry = registry_match[:registry]
            image = remaining.sub(%r{^#{Regexp.escape(registry)}/}, "") if registry
            return { "registry" => registry, "image" => image, "tag" => tag, "digest" => digest }
          end
        end

        # No registry, just image name
        { "registry" => nil, "image" => remaining, "tag" => tag, "digest" => digest }
      end
      # rubocop:enable Metrics/PerceivedComplexity

      sig do
        params(
          key: String,
          value: String,
          hash: T::Hash[T.untyped, T.untyped],
          current_path: T::Array[String]
        ).returns(T::Array[T::Hash[Symbol, String]])
      end
      def handle_string_value(key, value, hash, current_path)
        images = []
        if key == "repository" && hash["tag"].is_a?(String)
          image_string = "#{value}:#{hash['tag']}"
          # Only prepend registry if it's not already in the repository value
          if hash["registry"].is_a?(String) && !value.start_with?("#{hash['registry']}/")
            image_string = "#{hash['registry']}/#{image_string}"
          end
          images << { path: current_path.join("."), image: image_string }
        elsif key == "image" && value.include?(":")
          images << { path: current_path.join("."), image: value }
        end
        images
      end

      sig do
        params(value: T::Array[T.untyped], current_path: T::Array[String]).returns(T::Array[T::Hash[Symbol, String]])
      end
      def handle_array_value(value, current_path)
        images = []
        value.each_with_index do |item, index|
          images.concat(find_images_in_hash(item, current_path + [index.to_s])) if item.is_a?(Hash)
        end
        images
      end

      sig { params(hash: T.untyped, path: T.untyped).returns(T::Array[T.untyped]) }
      def find_images_in_hash(hash, path = [])
        images = []

        hash.each do |key, value|
          current_path = path + [key.to_s]

          if value.is_a?(String) && (key.to_s == "image" || key.to_s == "repository")
            images.concat(handle_string_value(key.to_s, value, hash, current_path))
          elsif value.is_a?(Hash)
            images.concat(find_images_in_hash(value, current_path))
          elsif value.is_a?(Array)
            images.concat(find_images_in_hash(value, current_path))
          end
        end

        images
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def helm_chart_files
        dependency_files.select { |file| file.name.match(CHART_YAML) }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def helm_values_files
        dependency_files.select { |file| file.name.match(VALUES_YAML) }
      end

      sig { override.returns(String) }
      def package_manager
        "helm"
      end

      sig { override.returns(String) }
      def file_type
        "helm chart"
      end

      sig { override.void }
      def check_required_files
        return if dependency_files.any?

        raise "No #{file_type} files!"
      end
    end
  end
end

Dependabot::FileParsers.register(
  "helm",
  Dependabot::Helm::FileParser
)
