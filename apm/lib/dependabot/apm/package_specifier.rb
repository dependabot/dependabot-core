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
    # HTTPS and SSH clone URLs both resolve to an `https://host[:port]/owner/repo`
    # remote, since Dependabot enumerates tags over HTTPS with a token. An
    # `https://` source keeps its authority verbatim, including a custom port
    # (`github.com:8443` is a distinct endpoint). An `ssh://` (or `git@host:`
    # SCP) source reaches the same repositories over HTTPS, so it resolves there
    # and its SSH port (e.g. `:2222`) is dropped, as it is not an HTTPS port.
    # Host classification (GitHub-family, Azure DevOps) always ignores the port.
    # `http://` and `git://` URLs name a different endpoint than HTTPS and are
    # not silently rewritten; they are out of scope for v1 and resolve to `nil`.
    #
    # Virtual package paths (`owner/repo/skills/review`) are a GitHub-family
    # shorthand, since GitHub repositories are always `owner/repo`. That covers
    # github.com and GitHub Enterprise Cloud data-residency hosts (`*.ghe.com`),
    # which APM also resolves as GitHub. On other hosts (e.g. GitLab) the whole
    # path is treated as the repository so nested subgroups resolve to the
    # correct remote; virtual packages there are out of scope for v1, as is
    # self-hosted GHES on an arbitrary hostname that cannot be recognised from
    # the host alone.
    #
    # Azure DevOps hosts (`dev.azure.com`, `ssh.dev.azure.com` and legacy
    # `*.visualstudio.com`) expose repositories at `org/project/_git/repo`, a
    # structure this generic `owner/repo` builder cannot construct, so their
    # entries are out of scope for v1 and resolve to `nil`.
    #
    # Local path entries (`./pkg`, `../pkg`, `/pkg`, `~/pkg`, and their Windows
    # `.\`/`..\`/`~\` forms) are not versioned by a remote git host and resolve
    # to `nil`, as do entries we cannot confidently parse.
    class PackageSpecifier
      extend T::Sig

      DEFAULT_HOST = "github.com"

      # Azure DevOps Services hosts. Their repositories live at
      # `org/project/_git/repo`, a structure this generic owner/repo builder
      # cannot express, so ADO entries are out of scope for v1 (see README) and
      # are skipped rather than resolved to a wrong remote. Legacy
      # per-organisation hosts match the `.visualstudio.com` suffix separately.
      AZURE_DEVOPS_HOSTS = %w(dev.azure.com ssh.dev.azure.com).freeze

      # SCP-style SSH shorthand `user@host:path`. APM accepts any valid SSH
      # username here (not only `git@`), so match any user that has no `:` or
      # `/` (either would signal a URL scheme or path rather than an SCP user).
      # The user is discarded — only the host and path determine the git
      # coordinates, just as URL_STYLE drops its `user@` info.
      SCP_STYLE = %r{\A(?<user>[^@:/\s]+)@(?<host>[^:/\s]+):(?<path>.+)\z}
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

        build(host: host, path: path, ref: ref, default_host: default_host)
      end

      # True when `raw` is the string shorthand form (`[host/]owner/repo…`)
      # rather than an explicit git reference (`https://`, `http://`, `ssh://git@`,
      # an SCP `git@host:path`, or any `.git`-suffixed ref). When an apm manifest
      # configures a default registry, APM routes shorthand entries through it
      # instead of Git, so the parser skips them (registry dependencies are out
      # of scope for v1). This mirrors APM's `_is_explicit_git_form`, which
      # routes URL, SCP and `.git` forms to Git even when a default registry is
      # configured -- they are the escape hatch and are never registry-routed.
      sig { params(raw: Object).returns(T::Boolean) }
      def self.shorthand?(raw)
        return false unless raw.is_a?(String)

        spec = raw.strip.partition("#").first.to_s
        return false if spec.empty? || local_path?(spec)

        # A `.git` suffix marks an explicit git reference (as APM's
        # `_is_explicit_git_form` treats it), so it is a Git escape hatch rather
        # than a registry-routed shorthand even without a transport scheme.
        return false if spec.downcase.end_with?(".git")

        !spec.match?(SCP_STYLE) && !spec.match?(URL_STYLE)
      end

      sig do
        params(host: String, path: String, ref: String, default_host: String)
          .returns(T.nilable(Dependabot::Apm::PackageSpecifier))
      end
      def self.build(host:, path:, ref:, default_host: DEFAULT_HOST)
        # DNS hostnames are case-insensitive, so canonicalise to lowercase once
        # here; repository splitting, naming and credential-host matching all key
        # off `host` and must agree on e.g. `GitHub.com` == `github.com`.
        host = host.downcase
        # Azure DevOps clone URLs are `org/project/_git/repo`, which this generic
        # owner/repo builder cannot construct, so ADO shorthands and URLs are not
        # versioned in v1 (see README). Skip them rather than emit a wrong remote
        # that GitCommitChecker would query as a non-repository endpoint.
        return nil if azure_devops_host?(host)

        segments = path.delete_suffix(".git").split("/").reject(&:empty?)
        owner = segments[0]
        return nil if owner.nil? || segments[1].nil?

        repo, sub_path = repository_and_sub_path(host, segments)

        # GitHub-family owner/repo paths are case-insensitive, so canonicalise
        # them to lowercase to give each repository a single stable identity.
        # Other hosts (e.g. GitLab) are case-sensitive and MUST preserve casing,
        # as must virtual sub paths (they address entries inside the repo tree).
        if github_family?(host)
          owner = owner.downcase
          repo = repo.downcase
        end

        new(
          host: host,
          owner: owner,
          repo: repo,
          sub_path: sub_path.empty? ? nil : sub_path,
          ref: ref.empty? ? nil : ref,
          default_host: default_host.downcase
        )
      end

      # Splits the path segments (after `owner`) into a repository path and an
      # optional virtual sub path. GitHub-family hosts (github.com and GitHub
      # Enterprise Cloud `*.ghe.com`) always expose repositories as exactly
      # `owner/repo`, so any deeper segments are an APM virtual package path.
      # Other hosts (e.g. GitLab) allow repositories nested at arbitrary subgroup
      # depth, and APM resolves the repository/virtual boundary host-specifically
      # rather than from the path alone; to avoid querying a shallower, wrong
      # remote we keep the whole path as the repository there. Virtual packages
      # outside the GitHub family are therefore out of scope for v1.
      sig { params(host: String, segments: T::Array[String]).returns([String, String]) }
      def self.repository_and_sub_path(host, segments)
        if github_family?(host)
          [T.must(segments[1]), (segments[2..] || []).join("/")]
        else
          [(segments[1..] || []).join("/"), ""]
        end
      end

      # GitHub-family hosts share the strict `owner/repo` boundary (any deeper
      # segments are an APM virtual package path) and case-insensitive owner and
      # repo names. That is github.com plus GitHub Enterprise Cloud
      # data-residency hosts (`*.ghe.com`), which APM resolves as GitHub too.
      # Self-hosted GHES uses arbitrary hostnames that cannot be recognised from
      # the host alone, so it is not detected here -- a follow-up for once host
      # configuration is threaded through the parser.
      sig { params(host: String).returns(T::Boolean) }
      def self.github_family?(host)
        hostname = hostname_without_port(host)
        hostname == DEFAULT_HOST || hostname.end_with?(".ghe.com")
      end

      # True for Azure DevOps Services hosts: dev.azure.com, its SSH alias, and
      # legacy per-organisation `*.visualstudio.com` hosts. APM special-cases
      # these with `org/project/_git/repo` clone URLs; v1 does not build those,
      # so such entries are skipped (see README) rather than resolved to a wrong
      # remote.
      sig { params(host: String).returns(T::Boolean) }
      def self.azure_devops_host?(host)
        hostname = hostname_without_port(host)
        AZURE_DEVOPS_HOSTS.include?(hostname) || hostname.end_with?(".visualstudio.com")
      end

      # The hostname with any `:port` suffix removed. Host-family classification
      # keys off the hostname alone: the port is part of the authority that
      # `git_url` and `name` keep, but it must not change which family a URL
      # belongs to (`github.com:8443` is still GitHub, `foo.ghe.com:8443` still
      # GHE Cloud). Only a trailing `:<digits>` is stripped, so bracketed IPv6
      # authorities are left intact.
      sig { params(host: String).returns(String) }
      def self.hostname_without_port(host)
        host.sub(/:\d+\z/, "")
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
          host = T.must(m[:host])
          case m[:scheme]
          when "https"
            # HTTPS is the transport we query, so keep the authority verbatim,
            # including any explicit port: `github.com:8443` is a distinct
            # endpoint from `github.com` and must stay that way.
            return [host, m[:path]]
          when "ssh"
            # SSH reaches the same repositories as HTTPS on that host, and
            # Dependabot enumerates tags over HTTPS with a token, so resolve
            # ssh:// URIs over HTTPS. The SSH port (e.g. the `:2222` on
            # `ssh://git@host:2222/...`) is not an HTTPS port, so drop it.
            return [host.sub(/:\d+\z/, ""), m[:path]]
          else
            # http:// and git:// name a different endpoint than HTTPS (a
            # distinct port, and for http an unencrypted service). We only query
            # over HTTPS, so rather than silently rewrite them to a possibly
            # wrong remote we treat them as out of scope for v1 (see README);
            # returning a nil path makes `parse` yield nil.
            return [host, nil]
          end
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
          ref: T.nilable(String),
          default_host: String
        ).void
      end
      def initialize(host:, owner:, repo:, sub_path: nil, ref: nil, default_host: DEFAULT_HOST)
        @host = host
        @owner = owner
        @repo = repo
        @sub_path = sub_path
        @ref = ref
        @default_host = default_host
      end

      sig { returns(String) }
      def git_url
        "https://#{host}/#{owner}/#{repo}"
      end

      # The dependency name shown to users. Repositories on the manifest's
      # default host -- the configured `default_host`, or github.com when unset
      # -- keep the familiar `owner/repo` shorthand, matching how APM keys the
      # dependency; repositories on any other host are namespaced by host to
      # stay unique. Comparing against the effective default (rather than a
      # hard-coded github.com) means a manifest-selected `default_host` is
      # stripped too, so dependency-name ignore rules and deduplication use the
      # same identity APM does. A virtual package (sub path) is namespaced by
      # that path too: APM keys virtual packages by repository plus path, so
      # `org/mono/skills/review` and `org/mono/skills/security` must remain
      # distinct dependencies rather than collapse into one `org/mono` entry
      # that DependencySet would deduplicate.
      sig { returns(String) }
      def name
        repo_name = host == @default_host ? "#{owner}/#{repo}" : "#{host}/#{owner}/#{repo}"
        virtual_path = sub_path
        virtual_path ? "#{repo_name}/#{virtual_path}" : repo_name
      end
    end
  end
end
