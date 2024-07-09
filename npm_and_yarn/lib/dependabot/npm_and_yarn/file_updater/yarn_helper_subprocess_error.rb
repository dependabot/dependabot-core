# typed: true
# frozen_string_literal: true

require "dependabot/errors"

module Dependabot
  module NpmAndYarn
    YARN_ERROR_CODES = {
      "YN0000" => "Unnamed error",
      "YN0001" => "Exception error",
      "YN0002" => "Missing peer dependency",
      "YN0003" => "Cyclic dependencies",
      "YN0004" => "Disabled build scripts",
      "YN0005" => "Build disabled",
      "YN0006" => "Soft link build",
      "YN0007" => "Must build",
      "YN0008" => "Must rebuild",
      "YN0009" => "Build failed",
      "YN0010" => "Resolver not found",
      "YN0011" => "Fetcher not found",
      "YN0012" => "Linker not found",
      "YN0013" => "Fetch not cached",
      "YN0014" => "Yarn import failed",
      "YN0015" => "Remote invalid",
      "YN0016" => "Remote not found",
      "YN0017" => "Resolution pack error",
      "YN0018" => "Cache checksum mismatch",
      "YN0019" => "Unused cache entry",
      "YN0020" => "Missing lockfile entry",
      "YN0021" => "Workspace not found",
      "YN0022" => "Too many matching workspaces",
      "YN0023" => "Constraints missing dependency",
      "YN0024" => "Constraints incompatible dependency",
      "YN0025" => "Constraints extraneous dependency",
      "YN0026" => "Constraints invalid dependency",
      "YN0027" => "Can't suggest resolutions",
      "YN0028" => "Frozen lockfile exception",
      "YN0029" => "Cross drive virtual local",
      "YN0030" => "Fetch failed",
      "YN0031" => "Dangerous node_modules",
      "YN0032" => "Node gyp injected",
      "YN0046" => "Automerge failed to parse",
      "YN0047" => "Automerge immutable",
      "YN0048" => "Automerge success",
      "YN0049" => "Automerge required",
      "YN0050" => "Deprecated CLI settings",
      "YN0059" => "Invalid range peer dependency",
      "YN0060" => "Incompatible peer dependency",
      "YN0061" => "Deprecated package",
      "YN0062" => "Incompatible OS",
      "YN0063" => "Incompatible CPU",
      "YN0068" => "Unused package extension",
      "YN0069" => "Redundant package extension",
      "YN0071" => "NM can't install external soft link",
      "YN0072" => "NM preserve symlinks required",
      "YN0074" => "NM hardlinks mode downgraded",
      "YN0075" => "Prolog instantiation error",
      "YN0076" => "Incompatible architecture",
      "YN0077" => "Ghost architecture",
      "YN0078" => "Resolution mismatch",
      "YN0080" => "Network disabled",
      "YN0081" => "Network unsafe HTTP",
      "YN0082" => "Resolution failed",
      "YN0083" => "Automerge git error",
      "YN0085" => "Updated resolution record",
      "YN0086" => "Explain peer dependencies CTA",
      "YN0087" => "Migration success",
      "YN0088" => "Version notice",
      "YN0089" => "Tips notice",
      "YN0090" => "Offline mode enabled"
    }.freeze

    class YarnHelperSubprocessFailed < Dependabot::SharedHelpers::HelperSubprocessFailed
      def initialize(message:, error_context:, error_class: nil, trace: nil)
        normalized_message = self.class.normalize_yarn_error(message)
        super(
          message: normalized_message,
          error_context: error_context,
          error_class: error_class || self.class.name,
          trace: trace
        )
      end

      def self.normalize_yarn_error(message)
        if message =~ /(YN\d{4})/
          code = ::Regexp.last_match(1)
          return "#{YARN_ERROR_CODES[code]} (Yarn error code: #{code})" if YARN_ERROR_CODES.key?(code)
        end
        message
      end
    end
  end
end
