# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/source"
require "dependabot/terraform/version"

module Dependabot
  module Terraform
    # Terraform::RegistryClient is a basic API client to interact with a
    # terraform registry: https://www.terraform.io/docs/registry/api.html
    class RegistryClient
      PUBLIC_HOSTNAME = "registry.terraform.io"

      def initialize(hostname:)
        @hostname = hostname
      end

      # Fetch all the versions of a module, and return a Version
      # representation of them.
      #
      # @param identifier [String] the identifier for the dependency, i.e:
      # "hashicorp/consul/aws"
      # @return [Array<Dependabot::Terraform::Version>]
      # @raise [RuntimeError] when the versions cannot be retrieved
      def all_module_versions(identifier:)
        # TODO: Implement service discovery for custom registries
        return [] unless hostname == PUBLIC_HOSTNAME

        response = get(endpoint: "modules/#{identifier}/versions")

        JSON.parse(response).
          fetch("modules").first.fetch("versions").
          map { |release| version_class.new(release.fetch("version")) }
      end

      # Fetch the "source" for a module. We use the API to fetch
      # the source for a dependency, this typically points to a source code
      # repository, and then instantiate a Dependabot::Source object that we
      # can use to fetch Metadata about a specific version of the dependency.
      #
      # @param dependency [Dependabot::Dependency] the dependency who's source
      # we're attempting to find
      # @return Dependabot::Source
      # @raise [RuntimeError] when the source cannot be retrieved
      def source(dependency:)
        # TODO: Implement service discovery for custom registries
        return unless hostname == PUBLIC_HOSTNAME

        endpoint = "modules/#{dependency.name}/#{dependency.version}"
        response = get(endpoint: endpoint)

        source_url = JSON.parse(response).fetch("source")
        Source.from_url(source_url) if source_url
      end

      private

      attr_reader :hostname

      def get(endpoint:)
        url = "https://#{hostname}/v1/#{endpoint}"

        response = Excon.get(
          url,
          idempotent: true,
          **SharedHelpers.excon_defaults
        )

        raise "Response from registry was #{response.status}" unless response.status == 200

        response.body
      end

      def version_class
        Version
      end
    end
  end
end
