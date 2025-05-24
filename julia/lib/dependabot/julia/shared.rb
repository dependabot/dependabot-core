# typed: strong
# frozen_string_literal: true

module Dependabot
  module Julia
    module Shared
      extend T::Sig

      PROJECT_NAMES = T.let(["Project.toml", "JuliaProject.toml"].freeze, T::Array[String])

      MANIFEST_REGEX = T.let(/Manifest(?:-v[\d.]+)?\.toml$/i, Regexp)

      sig { params(version: String).returns(T::Array[String]) }
      def self.manifest_names(version)
        names = ["Manifest.toml"]

        if version
          ver_part = version.delete(".")
          names.unshift("Manifest-v#{ver_part}.toml")
        end

        names
      end
    end
  end
end
