# frozen_string_literal: true

require "docker_registry2"

require "dependabot/file_updaters/base"
require "dependabot/errors"

module Dependabot
  module FileUpdaters
    module Docker
      class Docker < Dependabot::FileUpdaters::Base
        FROM_REGEX = /[Ff][Rr][Oo][Mm]/

        def self.updated_files_regex
          [/^Dockerfile$/]
        end

        def updated_dependency_files
          [updated_file(file: dockerfile, content: updated_dockerfile_content)]
        end

        private

        def dependency
          # Dockerfiles will only ever be updating a single dependency
          dependencies.first
        end

        def check_required_files
          %w(Dockerfile).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def updated_dockerfile_content
          if specified_with_digest?
            update_digest(dockerfile.content)
          else
            update_tag(dockerfile.content)
          end
        end

        def update_digest(content)
          old_declaration =
            if private_registry_url
              "#{private_registry_url}/"
            else
              ""
            end
          old_declaration += "#{dependency.name}@#{old_digest}"
          escaped_declaration = Regexp.escape(old_declaration)
          old_declaration_regex = /^#{FROM_REGEX}\s+#{escaped_declaration}/

          content.gsub(old_declaration_regex) do |old_dec|
            old_dec.gsub("@#{old_digest}", "@#{new_digest}")
          end
        end

        def update_tag(content)
          old_declaration =
            if private_registry_url
              "#{private_registry_url}/"
            else
              ""
            end
          old_declaration += "#{dependency.name}:#{dependency.previous_version}"
          escaped_declaration = Regexp.escape(old_declaration)

          old_declaration_regex = /^#{FROM_REGEX}\s+#{escaped_declaration}/

          content.gsub(old_declaration_regex) do |old_dec|
            old_dec.gsub(
              ":#{dependency.previous_version}",
              ":#{dependency.version}"
            )
          end
        end

        def dockerfile
          @dockerfile ||= dependency_files.find { |f| f.name == "Dockerfile" }
        end

        def specified_with_digest?
          dependency.requirements.first.fetch(:source).fetch(:type) == "digest"
        end

        def new_digest
          @attempt = 1
          @new_digest ||=
            begin
              image = dependency.name
              repo = image.split("/").count < 2 ? "library/#{image}" : image
              tag = dependency.version

              response = registry_client.dohead "/v2/#{repo}/manifests/#{tag}"
              response.headers.fetch(:docker_content_digest)
            rescue RestClient::Exceptions::Timeout
              @attempt += 1
              raise if @attempt > 3
              retry
            end
        end

        def old_digest
          @attempt = 1
          @old_digest ||=
            begin
              image = dependency.name
              repo = image.split("/").count < 2 ? "library/#{image}" : image
              tag = dependency.previous_version

              response = registry_client.dohead "/v2/#{repo}/manifests/#{tag}"
              response.headers.fetch(:docker_content_digest)
            rescue RestClient::Exceptions::Timeout
              @attempt += 1
              raise if @attempt > 3
              retry
            end
        end

        def private_registry_url
          dependency.requirements.first[:source][:registry]
        end

        def private_registry_credentials
          credentials.find { |cred| cred["registry"] == private_registry_url }
        end

        def registry_client
          if private_registry_url && !private_registry_credentials
            raise PrivateSourceNotReachable, private_registry_url
          end

          @registry_client ||=
            if private_registry_url
              DockerRegistry2::Registry.new(
                "https://#{private_registry_url}",
                user: private_registry_credentials["username"],
                password: private_registry_credentials["password"]
              )
            else
              DockerRegistry2::Registry.new("https://registry.hub.docker.com")
            end
        end
      end
    end
  end
end
