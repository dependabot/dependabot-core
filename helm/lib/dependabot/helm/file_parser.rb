# typed: strict
# frozen_string_literal: true

require "yaml"
require "dependabot/shared/shared_file_parser"
require "dependabot/helm/package_manager"

module Dependabot
  module Helm
    class FileParser < Dependabot::Shared::SharedFileParser
      extend T::Sig

      # Use the regex patterns from SharedFileParser for image parsing
      # Define Helm-specific patterns
      CHART_NAME = /[a-zA-Z0-9-_.]+/
      CHART_VERSION = /[0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9-.]+)?/
      REPO_URL = %r{(?:https?://|oci://|file://)[^\s'"]+}

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: PackageManager.new
          ),
          T.nilable(Ecosystem)
        )
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        # Parse Chart.yaml files (Helm v3)
        parse_chart_yaml_files(dependency_set)

        # Parse values.yaml files for container image references
        parse_values_yaml_files(dependency_set)

        dependency_set.dependencies
      end

      private

      sig { params(dependency_set: DependencySet).void }
      def parse_chart_yaml_files(dependency_set)
        helm_chart_files.each do |chart_file|
          yaml = YAML.safe_load(T.must(chart_file.content), aliases: true)
          next unless yaml.is_a?(Hash)

          # Process chart dependencies (Helm v3 style)
          if yaml["dependencies"].is_a?(Array)
            yaml["dependencies"].each do |dep|
              next unless dep.is_a?(Hash) && dep["name"] && dep["version"] && dep["repository"]

              # Create a parsed_line hash in the format expected by build_dependency
              parsed_line = {
                "image" => dep["name"],
                "tag" => dep["version"],
                "registry" => nil,
                "digest" => nil
              }

              dependency = build_dependency(chart_file, parsed_line, dep["version"])

              # Update source with Helm-specific information
              dependency.requirements.first[:source] = {
                type: "helm_repo",
                url: dep["repository"]
              }

              dependency_set << dependency
            end
          end

          # Process appVersion as a dependency
          if yaml["appVersion"] && yaml["name"]
            version = yaml["appVersion"].to_s.delete_prefix("\"").delete_suffix("\"")

            # Create a parsed_line hash in the format expected by build_dependency
            parsed_line = {
              "image" => "#{yaml["name"]}-app",
              "tag" => version,
              "registry" => nil,
              "digest" => nil
            }

            dependency = build_dependency(chart_file, parsed_line, version)

            # Update with appVersion group
            dependency.requirements.first[:groups] = ["appVersion"]

            dependency_set << dependency
          end
        end
      end

      sig { params(dependency_set: DependencySet).void }
      def parse_values_yaml_files(dependency_set)
        helm_values_files.each do |values_file|
          yaml = YAML.safe_load(T.must(values_file.content), aliases: true)
          next unless yaml.is_a?(Hash)

          # Process container image references
          find_images_in_hash(yaml).each do |image_details|
            parsed_line = extract_image_details(image_details[:image])
            next unless parsed_line

            version = version_from(parsed_line)
            next unless version

            # Use the shared build_dependency method for creating dependencies
            dependency = build_dependency(values_file, parsed_line, version)

            # Update the source with path information for nested values
            dependency.requirements.first[:source] = dependency.requirements.first[:source].merge(path: image_details[:path])

            dependency_set << dependency
          end
        end
      end

      sig { params(image_string: String).returns(T.nilable(T::Hash[String, T.nilable(String)])) }
      def extract_image_details(image_string)
        # Skip if the string contains environment variables
        return nil if image_string.match?(/\${[^}]+}/)

        # Try to match the image string against our patterns
        registry_match = image_string.match(%r{^(#{REGISTRY}/)?})
        image_match = image_string.match(%r{#{IMAGE}})
        tag_match = image_string.match(%r{#{TAG}})
        digest_match = image_string.match(%r{#{DIGEST}})

        return nil unless image_match

        {
          "registry" => registry_match && registry_match[:registry],
          "image" => image_match[:image],
          "tag" => tag_match && tag_match[:tag],
          "digest" => digest_match && digest_match[:digest]
        }
      end

      sig { params(hash: T::Hash[T.untyped, T.untyped]).returns(T::Array[T::Hash[Symbol, String]]) }
      def find_images_in_hash(hash, path = [])
        images = []

        hash.each do |key, value|
          current_path = path + [key]

          if value.is_a?(String) && (key.to_s == "image" || key.to_s == "repository")
            if key.to_s == "repository" && hash["tag"].is_a?(String)
              # Handle repository + tag structure
              images << { path: current_path.join("."), image: "#{value}:#{hash["tag"]}" }
            elsif key.to_s == "image" && value.include?(":")
              # Handle direct image reference
              images << { path: current_path.join("."), image: value }
            end
          elsif value.is_a?(Hash)
            # Recursively search nested hashes
            images.concat(find_images_in_hash(value, current_path))
          elsif value.is_a?(Array)
            # Search through array items if they're hashes
            value.each_with_index do |item, index|
              if item.is_a?(Hash)
                images.concat(find_images_in_hash(item, current_path + [index.to_s]))
              end
            end
          end
        end

        images
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def helm_chart_files
        dependency_files.select { |file| file.name.end_with?("Chart.yaml") || file.name.end_with?("chart.yml") }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def helm_values_files
        dependency_files.select { |file| file.name.end_with?("values.yaml") || file.name.end_with?("values.yml") }
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
