# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Apm
    # Parses a single `dependencies.apm` entry from an `apm.yml` manifest into its
    # git coordinates. APM supports several equivalent forms for the same entry:
    #
    #   owner/repo                              GitHub shorthand, default branch
    #   owner/repo#v1.0.0                       Pinned to a tag, branch or SHA
    #   gitlab.com/acme/repo#v2.0              FQDN shorthand (any git host)
    #   gitlab.com/group/subgroup/repo#v2.0   Nested subgroup repo (non-GitHub)
    #   owner/repo/skills/review               Virtual subdirectory of a repo
    #   owner/repo/prompts/x.prompt.md#v1.0.0  Virtual file within a repo
    #   https://gitlab.com/acme/repo.git       Explicit HTTPS git URL
    #   git@gitlab.com:acme/repo.git           SSH SCP-style URL
    #   ssh://git@gitlab.com/acme/repo.git     SSH URI-style URL
    #
    # Virtual package paths (`owner/repo/skills/review`) are a GitHub-only
    # shorthand, since GitHub repositories are always `owner/repo`. On other
    # hosts the whole path is treated as the repository so nested subgroups
    # resolve to the correct remote; virtual packages there are out of scope for
    # v1.
    #
    # Local path entries (`./pkg`, `../pkg`, `/pkg`, `~/pkg`, and their Windows
    # `.\`/`..\`/`~\` forms) are not versioned by a remote git host and resolve
    # to `nil`, as do entries we cannot confidently parse.
    class PackageSpecifier
      extend T::Sig

      DEFAULT_HOST = "github.com"

      SCP_STYLE = /\Agit@(?<host>[^:]+):(?<path>.+)\z/
      # Matches https/git/ssh URIs, discarding any `user@` info (e.g. the
      # `git@` in an `ssh://git@host/owner/repo` URL) so only the host remains.
      URL_STYLE = %r{\A(?<scheme>https?|git|ssh)://(?:[^@/]+@)?(?<host>[^/]+)/(?<path>.+)\z}

      sig { returns(String) }
      attr_reader :host

      sig { returns(String) }
      attr_reader :owner

      sig { returns(String) }
      attr_reader :repo

      sig { returns(T.nilable(String)) }
      attr_reader :sub_path

      sig { returns(T.nilable(String)) }
      attr_reader :ref

      sig { params(raw: Object, default_host: String).returns(T.nilable(Dependabot::Apm::PackageSpecifier)) }
      def self.parse(raw, default_host: DEFAULT_HOST)
        return nil unless raw.is_a?(String)

        entry = raw.strip
        return nil if entry.empty? || local_path?(entry)

        spec, _, ref = entry.partition("#")
        host, path = split_host_and_path(spec, default_host)
        return nil unless path

        build(host: host, path: path, ref: ref)
      end

      sig do
        params(host: String, path: String, ref: String)
          .returns(T.nilable(Dependabot::Apm::PackageSpecifier))
      end
      def self.build(host:, path:, ref:)
        # DNS hostnames are case-insensitive, so canonicalise to lowercase once
        # here; repository splitting, naming and credential-host matching all key
        # off `host` and must agree on e.g. `GitHub.com` == `github.com`.
        host = host.downcase
        segments = path.delete_suffix(".git").split("/").reject(&:empty?)
        owner = segments[0]
        return nil if owner.nil? || segments[1].nil?

        repo, sub_path = repository_and_sub_path(host, segments)
        new(
          host: host,
          owner: owner,
          repo: repo,
          sub_path: sub_path.empty? ? nil : sub_path,
          ref: ref.empty? ? nil : ref
        )
      end

      # Splits the path segments (after `owner`) into a repository path and an
      # optional virtual sub path. GitHub repositories are always exactly
      # `owner/repo`, so any deeper segments are an APM virtual package path.
      # Other hosts (e.g. GitLab) allow repositories nested at arbitrary subgroup
      # depth, and APM resolves the repository/virtual boundary host-specifically
      # rather than from the path alone; to avoid querying a shallower, wrong
      # remote we keep the whole path as the repository there. Virtual packages
      # outside GitHub are therefore out of scope for v1.
      sig { params(host: String, segments: T::Array[String]).returns([String, String]) }
      def self.repository_and_sub_path(host, segments)
        if host == DEFAULT_HOST
          [T.must(segments[1]), (segments[2..] || []).join("/")]
        else
          [(segments[1..] || []).join("/"), ""]
        end
      end

      sig { params(entry: String).returns(T::Boolean) }
      def self.local_path?(entry)
        entry.start_with?("./", "../", "/", "~/", ".\\", "..\\", "~\\") ||
          entry == "." || entry == "~"
      end

      sig { params(spec: String, default_host: String).returns([String, T.nilable(String)]) }
      def self.split_host_and_path(spec, default_host)
        if (m = spec.match(SCP_STYLE))
          return [T.must(m[:host]), m[:path]]
        end

        if (m = spec.match(URL_STYLE))
          return [T.must(m[:host]), m[:path]]
        end

        first_segment = spec.split("/").first.to_s
        # A dot in the first path segment marks an FQDN host (GitHub owners never
        # contain a dot), e.g. `gitlab.com/acme/repo`.
        if first_segment.include?(".")
          [first_segment, spec.split("/")[1..].to_a.join("/")]
        else
          [default_host, spec]
        end
      end

      sig do
        params(
          host: String,
          owner: String,
          repo: String,
          sub_path: T.nilable(String),
          ref: T.nilable(String)
        ).void
      end
      def initialize(host:, owner:, repo:, sub_path: nil, ref: nil)
        @host = host
        @owner = owner
        @repo = repo
        @sub_path = sub_path
        @ref = ref
      end

      sig { returns(String) }
      def git_url
        "https://#{host}/#{owner}/#{repo}"
      end

      # The dependency name shown to users. GitHub-hosted repos keep the familiar
      # `owner/repo` shorthand; other hosts are namespaced by host to stay unique.
      # A virtual package (sub path) is namespaced by that path too: APM keys
      # virtual packages by repository plus path, so `org/mono/skills/review` and
      # `org/mono/skills/security` must remain distinct dependencies rather than
      # collapse into one `org/mono` entry that DependencySet would deduplicate.
      sig { returns(String) }
      def name
        repo_name = host == DEFAULT_HOST ? "#{owner}/#{repo}" : "#{host}/#{owner}/#{repo}"
        virtual_path = sub_path
        virtual_path ? "#{repo_name}/#{virtual_path}" : repo_name
      end
    end
  end
end
