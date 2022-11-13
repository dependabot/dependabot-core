# frozen_string_literal: true

require "docker_registry2"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/errors"

module Dependabot
  module Docker
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"

      # Details of Docker regular expressions is at
      # https://github.com/docker/distribution/blob/master/reference/regexp.go
      DOMAIN_COMPONENT = /(?:[[:alnum:]]|[[:alnum:]][[[:alnum:]]-]*[[:alnum:]])/
      DOMAIN = /(?:#{DOMAIN_COMPONENT}(?:\.#{DOMAIN_COMPONENT})+)/
      REGISTRY = /(?<registry>#{DOMAIN}(?::\d+)?)/

      NAME_COMPONENT = /(?:[a-z\d]+(?:(?:[._]|__|[-]*)[a-z\d]+)*)/
      IMAGE = %r{(?<image>#{NAME_COMPONENT}(?:/#{NAME_COMPONENT})*)}

      FROM = /FROM/i
      PLATFORM = /--platform\=(?<platform>\S+)/
      TAG = /:(?<tag>[\w][\w.-]{0,127})/
      DIGEST = /@(?<digest>[^\s]+)/
      NAME = /\s+AS\s+(?<name>[\w-]+)/
      FROM_LINE =
        %r{^#{FROM}\s+(#{PLATFORM}\s+)?(#{REGISTRY}/)?
          #{IMAGE}#{TAG}?#{DIGEST}?#{NAME}?}x

      AWS_ECR_URL = /dkr\.ecr\.(?<region>[^.]+)\.amazonaws\.com/

      IMAGE_SPEC = %r{^(#{REGISTRY}/)?#{IMAGE}#{TAG}?#{DIGEST}?#{NAME}?}x

      def parse
        dependency_set = DependencySet.new

        dockerfiles.each do |dockerfile|
          dockerfile.content.each_line do |line|
            next unless FROM_LINE.match?(line)

            parsed_from_line = FROM_LINE.match(line).named_captures
            parsed_from_line["registry"] = nil if parsed_from_line["registry"] == "docker.io"

            version = version_from(parsed_from_line)
            next unless version

            dependency_set << Dependency.new(
              name: parsed_from_line.fetch("image"),
              version: version,
              package_manager: "docker",
              requirements: [
                requirement: nil,
                groups: [],
                file: dockerfile.name,
                source: source_from(parsed_from_line)
              ]
            )
          end
        end

        manifest_files.each do |file|
          dependency_set += workfile_file_dependencies(file)
        end

        dependency_set.dependencies
      end

      private

      def dockerfiles
        # The Docker file fetcher fetches Dockerfiles and yaml files. Reject yaml files.
        dependency_files.reject { |f| f.type == "file" && f.name.match?(/^[^\.]+\.ya?ml/i) }
      end

      def version_from(parsed_from_line)
        parsed_from_line.fetch("tag") || parsed_from_line.fetch("digest")
      end

      def source_from(parsed_from_line)
        source = {}

        source[:registry] = parsed_from_line.fetch("registry") if parsed_from_line.fetch("registry")

        source[:tag] = parsed_from_line.fetch("tag") if parsed_from_line.fetch("tag")

        source[:digest] = parsed_from_line.fetch("digest") if parsed_from_line.fetch("digest")

        source
      end

      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No Dockerfile!"
      end

      def workfile_file_dependencies(file)
        dependency_set = DependencySet.new

        resources = file.content.split(/^---$/).map(&:strip).reject(&:empty?) # assuming a yaml file
        resources.flat_map do |resource|
          json = YAML.safe_load(resource, aliases: true)
          images = deep_fetch_images(json).uniq

          images.each do |string|
            # TODO: Support Docker references and path references
            details = string.match(IMAGE_SPEC).named_captures
            details["registry"] = nil if details["registry"] == "docker.io"

            version = version_from(details)
            next unless version

            dependency_set << build_image_dependency(file, details, version)
          end
        end

        dependency_set
      rescue Psych::SyntaxError, Psych::DisallowedClass, Psych::BadAlias
        raise Dependabot::DependencyFileNotParseable, file.path
      end

      def build_image_dependency(file, details, version)
        Dependency.new(
          name: details.fetch("image"),
          version: version,
          package_manager: "docker",
          requirements: [
            requirement: nil,
            groups: [],
            file: file.name,
            source: source_from(details)
          ]
        )
      end

      def deep_fetch_images(json_obj)
        case json_obj
        when Hash then deep_fetch_images_from_hash(json_obj)
        when Array then json_obj.flat_map { |o| deep_fetch_images(o) }
        else []
        end
      end

      def deep_fetch_images_from_hash(json_object)
        img = json_object.fetch("image", nil)

        images =
          if !img.nil? && img.is_a?(String) && !img.empty?
            [img]
          elsif !img.nil? && img.is_a?(Hash) && !img.empty?
            parse_helm(img)
          else
            []
          end

        images + json_object.values.flat_map { |obj| deep_fetch_images(obj) }
      end

      def manifest_files
        # Dependencies include both Dockerfiles and yaml, select yaml.
        dependency_files.select { |f| f.type == "file" && f.name.match?(/^[^\.]+\.ya?ml/i) }
      end

      def parse_helm(img_hash)
        repo = img_hash.fetch("repository", nil)
        tag = img_hash.key?("tag") ? img_hash.fetch("tag", nil) : img_hash.fetch("version", nil)
        registry = img_hash.fetch("registry", nil)

        if !repo.nil? && !registry.nil? && !tag.nil?
          ["#{registry}/#{repo}:#{tag}"]
        elsif !repo.nil? && !tag.nil?
          ["#{repo}:#{tag}"]
        elsif !repo.nil?
          [repo]
        else
          []
        end
      end
    end
  end
end

Dependabot::FileParsers.register("docker", Dependabot::Docker::FileParser)
