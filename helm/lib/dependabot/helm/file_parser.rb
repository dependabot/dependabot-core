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
      VALUES_YAML = /.*(^|\/)values(?:\.[\w-]+)?\.ya?ml$/i
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
        params(yaml: T::Hash[T.untyped, T.untyped], chart_file: Dependabot::DependencyFile,
               dependency_set: DependencySet).void
      end
      def parse_dependencies(yaml, chart_file, dependency_set)
        yaml["dependencies"].each do |dep|
          next unless dep.is_a?(Hash) && dep["name"] && dep["version"]

          parsed_line = {
            "image" => dep["name"],
            "tag" => dep["version"],
            "registry" => repository_from_registry(dep["repository"]),
            "digest" => nil
          }

          dependency = build_dependency(chart_file, parsed_line, dep["version"])
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

      sig { params(image_string: String).returns(T.nilable(T::Hash[String, T.nilable(String)])) }
      def extract_image_details(image_string)
        return nil if image_string.match?(/\${[^}]+}/)

        registry_match = image_string.match(%r{^(#{REGISTRY}/)?}o)
        image_match = image_string.match(/#{IMAGE}/o)
        tag_match = image_string.match(/#{TAG}/o)
        digest_match = image_string.match(/#{DIGEST}/o)

        return nil unless image_match

        {
          "registry" => registry_match && registry_match[:registry],
          "image" => image_match[:image],
          "tag" => tag_match && tag_match[:tag],
          "digest" => digest_match && digest_match[:digest]
        }
      end

      sig do
        params(key: String, value: String, hash: T::Hash[T.untyped, T.untyped],
               current_path: T::Array[String]).returns(T::Array[T::Hash[Symbol, String]])
      end
      def handle_string_value(key, value, hash, current_path)
        images = []
        if key == "repository" && hash["tag"].is_a?(String)
          images << { path: current_path.join("."), image: "#{value}:#{hash['tag']}" }
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
