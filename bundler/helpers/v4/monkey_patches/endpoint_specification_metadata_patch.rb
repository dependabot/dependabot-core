# typed: false
# frozen_string_literal: true

require "bundler/endpoint_specification"

# Bundler 4 parses the metadata a registry's compact index (`/info/<gem>`)
# returns per gem version. Its guard is `next unless v`, but an empty array
# `[]` is truthy, so for an empty `checksum` it calls `Checksum.from_api(nil)`
# -> `nil.match?(...)` and raises `Bundler::GemspecError` ("There was an error
# parsing the metadata for the gem ..."), aborting the whole resolution.
#
# GitHub Packages serves this empty-checksum shape for some old gems (e.g.
# failbot 2.0.1), so one such gem blocks every update for the repo. Bundler 2
# didn't parse compact-index checksums, so this only surfaced once the updater
# moved to the Bundler 4 helper.
#
# Drop nil/empty metadata values before Bundler parses them. An empty checksum
# carries nothing to verify, so skipping it is safe; well-formed values (and
# genuinely malformed ones, which still raise) are untouched.
module BundlerEndpointSpecificationMetadataPatch
  def parse_metadata(data)
    if data.respond_to?(:reject)
      data = data.reject do |_key, value|
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end
    end

    super
  end
end

Bundler::EndpointSpecification.prepend(BundlerEndpointSpecificationMetadataPatch)
