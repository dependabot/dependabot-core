# typed: strict
# frozen_string_literal: true

require "docker_registry2"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/errors"
require "dependabot/docker/package_manager"
require "sorbet-runtime"

module Dependabot
  module Docker
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

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

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        dockerfiles.each do |dockerfile|
          T.must(dockerfile.content).each_line do |line|
            next unless FROM_LINE.match?(line)

            parsed_from_line = T.must(FROM_LINE.match(line)).named_captures
            parsed_from_line[REGISTERY_KEY] = nil if parsed_from_line[REGISTERY_KEY] == REGISTERY_DOMAIN

            version = version_from(parsed_from_line)
            next unless version

            dependency_set << Dependency.new(
              name: T.must(parsed_from_line.fetch(IMAGE_KEY)),
              version: version,
              package_manager: PACKAGE_MANAGER,
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

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager
          ),
          T.nilable(Ecosystem)
        )
      end

      private

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          PackageManager.new(docker_version || "latest"),
          T.nilable(Dependabot::Docker::PackageManager)
        )
      end

      sig { returns(T.nilable(String)) }
      def docker_version
        @docker_version ||= T.let(
          begin
            dockerfile = dockerfiles.find { |f| f.name == "Dockerfile" }
            return unless dockerfile

            dockerfile.content&.match(/FROM docker:(?<version>[0-9.]+)/)&.named_captures&.fetch(VERSION_KEY)
          end,
          T.nilable(String)
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def dockerfiles
        # The Docker file fetcher fetches Dockerfiles and yaml files. Reject yaml files.
        dependency_files.reject { |f| f.type == FILE_TYPE && f.name.match?(YAML_REGEXP) }
      end

      sig { params(parsed_from_line: T::Hash[String, T.nilable(String)]).returns(T.nilable(String)) }
      def version_from(parsed_from_line)
        parsed_from_line.fetch(TAG_KEY) || parsed_from_line.fetch(DIGEST_KEY)
      end

      sig { params(parsed_from_line: T::Hash[String, T.nilable(String)]).returns(T::Hash[String, T.nilable(String)]) }
      def source_from(parsed_from_line)
        source = {}

        source[:registry] = parsed_from_line.fetch(REGISTERY_KEY) if parsed_from_line.fetch(REGISTERY_KEY)

        source[:tag] = parsed_from_line.fetch(TAG_KEY) if parsed_from_line.fetch(TAG_KEY)

        source[:digest] = parsed_from_line.fetch(DIGEST_KEY) if parsed_from_line.fetch(DIGEST_KEY)

        source
      end

      sig { override.void }
      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No #{MANIFEST_FILE}!"
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

            details[REGISTERY_KEY] = nil if details[REGISTERY_KEY] == REGISTERY_DOMAIN

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
          name: details.fetch(IMAGE_KEY),
          version: version,
          package_manager: PACKAGE_MANAGER,
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
        img = json_object.fetch(IMAGE_KEY, nil)

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
        dependency_files.select { |f| f.type == FILE_TYPE && f.name.match?(YAML_REGEXP) }
      end

      sig { params(img_hash: T::Hash[String, T.nilable(String)]).returns(T::Array[String]) }
      def parse_helm(img_hash)
        tag_value = img_hash.key?(TAG_KEY) ? img_hash.fetch(TAG_KEY, nil) : img_hash.fetch(VERSION_KEY, nil)
        return [] unless tag_value

        repo = img_hash.fetch(REPOSITORY_KEY, nil)
        return [] unless repo

        tag_details = T.must(tag_value.to_s.match(TAG_WITH_DIGEST)).named_captures
        tag = tag_details[TAG_KEY]
        return [repo] unless tag

        registry = img_hash.fetch(REGISTERY_KEY, nil)
        digest = tag_details[DIGEST_KEY]

        image = "#{repo}:#{tag}"
        image.prepend("#{registry}/") if registry
        image << "@sha256:#{digest}/" if digest
        [image]
      end
    end
  end
end

Dependabot::FileParsers.register("docker", Dependabot::Docker::FileParser)
