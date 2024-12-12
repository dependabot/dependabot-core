# typed: strict
# frozen_string_literal: true

require "docker_registry2"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/errors"
require "sorbet-runtime"

module Dependabot
  module Docker
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      YAML_REGEXP = /^[^\.].*\.ya?ml$/i

      # Details of Docker regular expressions is at
      # https://github.com/docker/distribution/blob/master/reference/regexp.go
      DOMAIN_COMPONENT = /(?:[[:alnum:]]|[[:alnum:]][[[:alnum:]]-]*[[:alnum:]])/
      DOMAIN = /(?:#{DOMAIN_COMPONENT}(?:\.#{DOMAIN_COMPONENT})+)/
      REGISTRY = /(?<registry>#{DOMAIN}(?::\d+)?)/

      NAME_COMPONENT = /(?:[a-z\d]+(?:(?:[._]|__|[-]*)[a-z\d]+)*)/
      IMAGE = %r{(?<image>#{NAME_COMPONENT}(?:/#{NAME_COMPONENT})*)}

      FROM = /FROM/i
      PLATFORM = /--platform\=(?<platform>\S+)/
      TAG_NO_PREFIX = /(?<tag>[\w][\w.-]{0,127})/
      TAG = /:#{TAG_NO_PREFIX}/
      DIGEST = /(?<digest>[0-9a-f]{64})/
      NAME = /\s+AS\s+(?<name>[\w-]+)/
      FROM_LINE =
        %r{^#{FROM}\s+(#{PLATFORM}\s+)?(#{REGISTRY}/)?
          #{IMAGE}#{TAG}?(?:@sha256:#{DIGEST})?#{NAME}?}x
      TAG_WITH_DIGEST = /^#{TAG_NO_PREFIX}(?:@sha256:#{DIGEST})?/x

      AWS_ECR_URL = /dkr\.ecr\.(?<region>[^.]+)\.amazonaws\.com/

      IMAGE_SPEC = %r{^(#{REGISTRY}/)?#{IMAGE}#{TAG}?(?:@sha256:#{DIGEST})?#{NAME}?}x

      # rubocop:disable Metrics/AbcSize
      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        dockerfiles.each do |dockerfile|
          T.must(dockerfile.content).each_line do |line|
            next unless FROM_LINE.match?(line)

            parsed_from_line = T.must(FROM_LINE.match(line)).named_captures
            parsed_from_line["registry"] = nil if parsed_from_line["registry"] == "docker.io"

            version = version_from(parsed_from_line)
            next unless version

            dependency_set << Dependency.new(
              name: T.must(parsed_from_line.fetch("image")),
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
          if file.content && T.must(file.content).start_with?("\uFEFF")
            # 0xFEFF is the encoding for the byte order mark (BOM).  If a YAML file is loaded with a BOM it will parse
            # successfully, but will only load the first line.  To prevent this nearly empty object from being returned,
            # the BOM is manually detected and reported as a parse error.
            file_path = Pathname.new(file.directory).join(file.name).cleanpath.to_path
            msg = "The file appears to have been saved with a byte order mark (BOM).  This will prevent proper parsing."
            raise Dependabot::DependencyFileNotParseable.new(file_path, msg)
          end
          dependency_set += workfile_file_dependencies(file)
        end

        dependency_set.dependencies
      end
      # rubocop:enable Metrics/AbcSize

      private

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def dockerfiles
        # The Docker file fetcher fetches Dockerfiles and yaml files. Reject yaml files.
        dependency_files.reject { |f| f.type == "file" && f.name.match?(YAML_REGEXP) }
      end

      sig { params(parsed_from_line: T::Hash[String, T.nilable(String)]).returns(T.nilable(String)) }
      def version_from(parsed_from_line)
        parsed_from_line.fetch("tag") || parsed_from_line.fetch("digest")
      end

      sig { params(parsed_from_line: T::Hash[String, T.nilable(String)]).returns(T::Hash[String, T.nilable(String)]) }
      def source_from(parsed_from_line)
        source = {}

        source[:registry] = parsed_from_line.fetch("registry") if parsed_from_line.fetch("registry")

        source[:tag] = parsed_from_line.fetch("tag") if parsed_from_line.fetch("tag")

        source[:digest] = parsed_from_line.fetch("digest") if parsed_from_line.fetch("digest")

        source
      end

      sig { override.void }
      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No Dockerfile!"
      end

      sig { params(file: T.untyped).returns(Dependabot::FileParsers::Base::DependencySet) }
      def workfile_file_dependencies(file)
        dependency_set = DependencySet.new

        resources = file.content.split(/^---$/).map(&:strip).reject(&:empty?) # assuming a yaml file
        resources.flat_map do |resource|
          json = YAML.safe_load(resource, aliases: true)
          images = deep_fetch_images(json).uniq

          images.each do |string|
            # TODO: Support Docker references and path references
            details = string.match(IMAGE_SPEC)&.named_captures
            next if details.nil?

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

      sig do
        params(file: T.untyped, details: T.untyped,
               version: T.nilable(T.any(String, Dependabot::Version))).returns(Dependabot::Dependency)
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

      sig { params(json_obj: T.anything).returns(T.untyped) }
      def deep_fetch_images(json_obj)
        case json_obj
        when Hash then deep_fetch_images_from_hash(json_obj)
        when Array then json_obj.flat_map { |o| deep_fetch_images(o) }
        else []
        end
      end

      sig { params(json_object: T.untyped).returns(T::Array[T.untyped]) }
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

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def manifest_files
        # Dependencies include both Dockerfiles and yaml, select yaml.
        dependency_files.select { |f| f.type == "file" && f.name.match?(YAML_REGEXP) }
      end

      sig { params(img_hash: T::Hash[String, T.nilable(String)]).returns(T::Array[String]) }
      def parse_helm(img_hash)
        tag_value = img_hash.key?("tag") ? img_hash.fetch("tag", nil) : img_hash.fetch("version", nil)
        return [] unless tag_value

        repo = img_hash.fetch("repository", nil)
        return [] unless repo

        tag_details = T.must(tag_value.to_s.match(TAG_WITH_DIGEST)).named_captures
        tag = tag_details["tag"]
        return [repo] unless tag

        registry = img_hash.fetch("registry", nil)
        digest = tag_details["digest"]

        image = "#{repo}:#{tag}"
        image.prepend("#{registry}/") if registry
        image << "@sha256:#{digest}/" if digest
        [image]
      end
    end
  end
end

Dependabot::FileParsers.register("docker", Dependabot::Docker::FileParser)
