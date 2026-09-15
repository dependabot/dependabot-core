# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/notices"

module Dependabot
  module Julia
    # The PR notice explaining a standard library's compat entry. The entry
    # is derived from the versions the project can meet across its julia
    # compat range, not from the registry (README, "Standard Libraries"),
    # which the diff alone does not explain, least of all "< 0.0.1". The file
    # parser records the sources and the julia entry per project file in the
    # dependency metadata (FileParser#dependency_metadata).
    module StdlibCompatNotice
      extend T::Sig

      PSA_URL = "https://discourse.julialang.org/t/psa-compat-requirements-in-the-general-registry-are-changing/104958"

      # One notice per stdlib entry the update writes or widens
      sig { params(dependency: Dependabot::Dependency).returns(T::Array[Dependabot::Notice]) }
      def self.for_dependency(dependency)
        sources_by_file = T.cast(
          dependency.metadata[:julia_stdlib_sources],
          T.nilable(T::Hash[String, T::Array[T::Hash[Symbol, String]]])
        )
        return [] unless sources_by_file

        compat_by_file = T.cast(dependency.metadata[:julia_compat], T.nilable(T::Hash[String, String])) || {}

        dependency.requirements.filter_map do |requirement|
          file_name = requirement.file.to_s
          entry = requirement.requirement_string
          sources = sources_by_file[file_name]
          next unless entry && sources&.any?
          next if entry == previous_entry(dependency, file_name)

          build(dependency.name, file_name, entry, compat_by_file[file_name].to_s, sources)
        end
      end

      sig { params(dependency: Dependabot::Dependency, file_name: String).returns(T.nilable(String)) }
      def self.previous_entry(dependency, file_name)
        dependency.previous_requirements&.find { |req| req.file == file_name }&.requirement_string
      end
      private_class_method :previous_entry

      sig do
        params(
          name: String,
          file_name: String,
          entry: String,
          julia_compat: String,
          sources: T::Array[T::Hash[Symbol, String]]
        ).returns(Dependabot::Notice)
      end
      def self.build(name, file_name, entry, julia_compat, sources)
        julia_range = if julia_compat.empty?
                        "every Julia release, since `#{file_name}` has no `julia` compat entry"
                      else
                        "the Julia releases its `julia = \"#{julia_compat}\"` compat entry admits"
                      end
        reasons = sources.map { |source| source_line(name, source) }.join("\n")

        description = <<~MARKDOWN
          `#{name}` ships with Julia, and Pkg pins it to the bundled version, so its compat entry in \
          `#{file_name}` has to admit every version the project can meet across #{julia_range}, rather \
          than track the registry's latest release:

          #{reasons}

          Listing the lowest version of each compat line, and keeping whatever the entry already admitted, \
          gives `#{name} = "#{entry}"`. See the [stdlib compat PSA](#{PSA_URL}) for the background.
        MARKDOWN

        Dependabot::Notice.new(
          mode: Dependabot::Notice::NoticeMode::INFO,
          type: "julia_stdlib_compat_entry",
          package_manager_name: "Pkg",
          title: "Why `#{name} = \"#{entry}\"`",
          description: description,
          show_in_pr: true,
          show_alert: false
        )
      end
      private_class_method :build

      sig { params(name: String, source: T::Hash[Symbol, String]).returns(String) }
      def self.source_line(name, source)
        julia = source[:julia]
        versions = source[:versions]
        case source[:source]
        when "bundled"
          "- Julia #{julia} bundles `#{name}` #{versions}."
        when "upgradable"
          "- Julia #{julia} bundles `#{name}` as an upgradable standard library, so Pkg resolves it from the " \
          "registry there, and the newest #{newest(versions)} #{versions}."
        when "registry"
          "- On Julia #{julia}, `#{name}` is not a standard library and comes from the registry, and the newest " \
          "#{newest(versions)} #{versions}."
        when "test_sandbox"
          "- `Pkg.test()` on Julia #{julia} pinned standard libraries to version 0.0.0 in the test sandbox, " \
          "which the entry admits as `< 0.0.1`. Raising the `julia` compat entry to `1.10`, the current " \
          "long-term support release, would drop that bound."
        else
          "- Julia #{julia}: `#{name}` #{versions}."
        end
      end
      private_class_method :source_line

      # "1.11.5" is one release, "1.11.5 - 1.12.2" one per Julia release
      sig { params(versions: T.nilable(String)).returns(String) }
      def self.newest(versions)
        versions.to_s.include?(" - ") ? "releases that install there are" : "release that installs there is"
      end
      private_class_method :newest
    end
  end
end
