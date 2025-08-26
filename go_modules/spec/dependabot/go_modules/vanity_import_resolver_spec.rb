# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/go_modules/vanity_import_resolver"

RSpec.describe Dependabot::GoModules::VanityImportResolver do
  let(:resolver) { described_class.new(dependencies: dependencies) }
  let(:dependencies) { [] }

  describe "#initialize" do
    it "stores the dependencies" do
      dep = Dependabot::Dependency.new(
        name: "go.example.com/pkg",
        version: "v1.0.0",
        requirements: [],
        package_manager: "go_modules"
      )
      resolver = described_class.new(dependencies: [dep])
      expect(resolver.instance_variable_get(:@dependencies)).to eq([dep])
    end
  end

  describe "#has_vanity_imports?" do
    context "with no dependencies" do
      let(:dependencies) { [] }

      it "returns false" do
        expect(resolver.has_vanity_imports?).to be false
      end
    end

    context "with only public hosting provider dependencies" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/user/repo",
            version: "v1.0.0",
            requirements: [],
            package_manager: "go_modules"
          ),
          Dependabot::Dependency.new(
            name: "gitlab.com/group/project",
            version: "v1.0.0",
            requirements: [],
            package_manager: "go_modules"
          )
        ]
      end

      it "returns false" do
        expect(resolver.has_vanity_imports?).to be false
      end
    end

    context "with vanity import dependencies" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "go.example.com/pkg",
            version: "v1.0.0",
            requirements: [],
            package_manager: "go_modules"
          )
        ]
      end

      it "returns true" do
        expect(resolver.has_vanity_imports?).to be true
      end
    end

    context "with mixed dependencies" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/user/repo",
            version: "v1.0.0",
            requirements: [],
            package_manager: "go_modules"
          ),
          Dependabot::Dependency.new(
            name: "go.company.com/internal/utils",
            version: "v1.0.0",
            requirements: [],
            package_manager: "go_modules"
          )
        ]
      end

      it "returns true" do
        expect(resolver.has_vanity_imports?).to be true
      end
    end
  end

  describe "#vanity_dependencies" do
    context "with no dependencies" do
      let(:dependencies) { [] }

      it "returns empty array" do
        expect(resolver.vanity_dependencies).to eq([])
      end
    end

    context "with only public hosting provider dependencies" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/user/repo",
            version: "v1.0.0",
            requirements: [],
            package_manager: "go_modules"
          ),
          Dependabot::Dependency.new(
            name: "gitlab.com/group/project",
            version: "v1.0.0",
            requirements: [],
            package_manager: "go_modules"
          ),
          Dependabot::Dependency.new(
            name: "bitbucket.org/team/repo",
            version: "v1.0.0",
            requirements: [],
            package_manager: "go_modules"
          )
        ]
      end

      it "returns empty array" do
        expect(resolver.vanity_dependencies).to eq([])
      end
    end

    context "with vanity import dependencies" do
      let(:vanity_dep1) do
        Dependabot::Dependency.new(
          name: "go.example.com/pkg",
          version: "v1.0.0",
          requirements: [],
          package_manager: "go_modules"
        )
      end

      let(:vanity_dep2) do
        Dependabot::Dependency.new(
          name: "custom.company.com/internal/tools",
          version: "v1.0.0",
          requirements: [],
          package_manager: "go_modules"
        )
      end

      let(:dependencies) { [vanity_dep1, vanity_dep2] }

      it "returns only vanity import dependencies" do
        expect(resolver.vanity_dependencies).to contain_exactly(vanity_dep1, vanity_dep2)
      end
    end

    context "with mixed dependencies" do
      let(:github_dep) do
        Dependabot::Dependency.new(
          name: "github.com/user/repo",
          version: "v1.0.0",
          requirements: [],
          package_manager: "go_modules"
        )
      end

      let(:vanity_dep) do
        Dependabot::Dependency.new(
          name: "go.company.com/internal/utils",
          version: "v1.0.0",
          requirements: [],
          package_manager: "go_modules"
        )
      end

      let(:dependencies) { [github_dep, vanity_dep] }

      it "returns only vanity import dependencies" do
        expect(resolver.vanity_dependencies).to contain_exactly(vanity_dep)
      end
    end

    context "with edge case dependency names" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "localhost/test", # No dots in domain - should be filtered out
            version: "v1.0.0",
            requirements: [],
            package_manager: "go_modules"
          ),
          Dependabot::Dependency.new(
            name: "go.uber.org/zap", # Valid vanity import
            version: "v1.0.0",
            requirements: [],
            package_manager: "go_modules"
          )
        ]
      end

      it "only includes valid vanity imports with domain-like paths" do
        expect(resolver.vanity_dependencies.map(&:name)).to eq(["go.uber.org/zap"])
      end
    end
  end

  describe "#resolve_git_hosts" do
    let(:dependencies) do
      [
        Dependabot::Dependency.new(
          name: "go.example.com/pkg",
          version: "v1.0.0",
          requirements: [],
          package_manager: "go_modules"
        )
      ]
    end

    before do
      # Mock HTTP response for vanity import resolution
      response_body = <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="go-import" content="go.example.com/pkg git ssh://git@git.example.com/pkg">
          <meta name="go-source" content="go.example.com/pkg https://git.example.com/pkg https://git.example.com/pkg/tree/HEAD{/dir} https://git.example.com/pkg/tree/HEAD{/dir}/{file}#L{line}">
        </head>
        <body>Nothing to see here</body>
        </html>
      HTML

      stub_request(:get, "https://go.example.com/pkg?go-get=1")
        .to_return(status: 200, body: response_body)
    end

    it "resolves git hosts from vanity import responses" do
      git_hosts = resolver.resolve_git_hosts
      expect(git_hosts).to include("git.example.com")
    end

    it "memoizes the result" do
      # First call
      result1 = resolver.resolve_git_hosts
      # Second call should return the same cached result
      result2 = resolver.resolve_git_hosts
      expect(result1).to equal(result2)
    end

    context "when HTTP request fails" do
      before do
        stub_request(:get, "https://go.example.com/pkg?go-get=1")
          .to_raise(StandardError.new("Network error"))
      end

      it "falls back to prediction" do
        git_hosts = resolver.resolve_git_hosts
        # Should include predicted hosts based on domain pattern
        expect(git_hosts).to include("go.example.com")
        expect(git_hosts).to include("git.example.com")
      end
    end

    context "when HTTP returns non-200 status" do
      before do
        stub_request(:get, "https://go.example.com/pkg?go-get=1")
          .to_return(status: 404, body: "Not found")
      end

      it "falls back to prediction" do
        git_hosts = resolver.resolve_git_hosts
        expect(git_hosts).to include("go.example.com")
        expect(git_hosts).to include("git.example.com")
      end
    end

    context "when HTML response has malformed go-import meta tags" do
      before do
        stub_request(:get, "https://go.example.com/pkg?go-get=1")
          .to_return(status: 200, body: "<html><body>Invalid HTML</body></html>")
      end

      it "falls back to prediction" do
        git_hosts = resolver.resolve_git_hosts
        expect(git_hosts).to include("go.example.com")
        expect(git_hosts).to include("git.example.com")
      end
    end

    context "with no vanity dependencies" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/user/repo",
            version: "v1.0.0",
            requirements: [],
            package_manager: "go_modules"
          )
        ]
      end

      it "returns empty array" do
        expect(resolver.resolve_git_hosts).to eq([])
      end
    end
  end

  describe "#extract_git_hosts_from_go_import_meta" do
    let(:resolver) { described_class.new(dependencies: []) }

    it "extracts git hosts from valid go-import meta tags" do
      html = <<~HTML
        <meta name="go-import" content="go.example.com/pkg git ssh://git@git.example.com/pkg">
      HTML

      hosts = resolver.send(:extract_git_hosts_from_go_import_meta, html)
      expect(hosts).to eq(["git.example.com"])
    end

    it "extracts hosts from multiple go-import meta tags" do
      html = <<~HTML
        <meta name="go-import" content="go.example.com/pkg git ssh://git@git.example.com/pkg">
        <meta name="go-import" content="go.example.com/tools git https://code.example.com/tools">
      HTML

      hosts = resolver.send(:extract_git_hosts_from_go_import_meta, html)
      expect(hosts).to contain_exactly("git.example.com", "code.example.com")
    end

    it "handles different git URL formats" do
      html = <<~HTML
        <meta name="go-import" content="pkg1 git ssh://git@host1.com/repo">
        <meta name="go-import" content="pkg2 git git@host2.com:repo">
        <meta name="go-import" content="pkg3 git https://host3.com/repo">
      HTML

      hosts = resolver.send(:extract_git_hosts_from_go_import_meta, html)
      expect(hosts).to contain_exactly("host1.com", "host2.com", "host3.com")
    end

    it "returns empty array for malformed HTML" do
      html = "<html>No meta tags</html>"
      hosts = resolver.send(:extract_git_hosts_from_go_import_meta, html)
      expect(hosts).to eq([])
    end

    it "handles parsing errors gracefully" do
      html = "invalid html <meta"
      hosts = resolver.send(:extract_git_hosts_from_go_import_meta, html)
      expect(hosts).to eq([])
    end
  end

  describe "#predict_git_hosts_from_domain" do
    let(:resolver) { described_class.new(dependencies: []) }

    it "includes the domain itself" do
      hosts = resolver.send(:predict_git_hosts_from_domain, "go.company.com")
      expect(hosts).to include("go.company.com")
    end

    it "predicts git.domain pattern for multi-level domains" do
      hosts = resolver.send(:predict_git_hosts_from_domain, "go.company.com")
      expect(hosts).to include("git.company.com")
    end

    it "handles single-level domains" do
      hosts = resolver.send(:predict_git_hosts_from_domain, "localhost")
      expect(hosts).to include("localhost")
    end

    it "handles domains with multiple subdomains" do
      hosts = resolver.send(:predict_git_hosts_from_domain, "api.internal.company.com")
      expect(hosts).to include("api.internal.company.com")
      expect(hosts).to include("git.internal.company.com")
    end
  end

  describe "constants" do
    it "defines known public hosts" do
      expect(described_class::KNOWN_PUBLIC_HOSTS).to include("github.com")
      expect(described_class::KNOWN_PUBLIC_HOSTS).to include("gitlab.com")
      expect(described_class::KNOWN_PUBLIC_HOSTS).to include("bitbucket.org")
    end

    it "defines HTTP configuration constants" do
      expect(described_class::GO_GET_QUERY_PARAM).to eq("?go-get=1")
      expect(described_class::CONNECT_TIMEOUT_SECONDS).to eq(10)
      expect(described_class::READ_TIMEOUT_SECONDS).to eq(10)
    end

    it "defines regex patterns" do
      expect(described_class::GO_IMPORT_META_TAG_REGEX).to be_a(Regexp)
      expect(described_class::GIT_URL_HOST_REGEX).to be_a(Regexp)
      expect(described_class::VANITY_IMPORT_PATH_REGEX).to be_a(Regexp)
    end
  end

  describe "common vanity import scenarios" do
    context "with enterprise vanity imports (SSH URL handling)" do
      let(:dependencies) do
        [
          # Kubernetes client-go - common vanity import that redirects to GitHub
          Dependabot::Dependency.new(
            name: "k8s.io/client-go",
            version: "v0.30.0",
            requirements: [],
            package_manager: "go_modules"
          ),
          # Google APIs - another common vanity import
          Dependabot::Dependency.new(
            name: "google.golang.org/api",
            version: "v0.150.0",
            requirements: [],
            package_manager: "go_modules"
          ),
          # Corporate internal package with vanity domain
          Dependabot::Dependency.new(
            name: "code.enterprise.com/platform/auth",
            version: "v1.2.3",
            requirements: [],
            package_manager: "go_modules"
          ),
          # Regular GitHub dependency (should be ignored)
          Dependabot::Dependency.new(
            name: "github.com/stretchr/testify",
            version: "v1.8.4",
            requirements: [],
            package_manager: "go_modules"
          )
        ]
      end

      before do
        # Mock k8s.io/client-go -> redirects to GitHub with SSH URL (like customer issue)
        stub_request(:get, "https://k8s.io/client-go?go-get=1")
          .to_return(
            status: 200,
            body: <<~HTML
              <html>
              <head>
                <meta name="go-import" content="k8s.io/client-go git ssh://git@github.com/kubernetes/client-go">
                <meta name="go-source" content="k8s.io/client-go https://github.com/kubernetes/client-go https://github.com/kubernetes/client-go/tree/master{/dir} https://github.com/kubernetes/client-go/blob/master{/dir}/{file}#L{line}">
              </head>
              </html>
            HTML
          )

        # Mock google.golang.org/api -> redirects to googlesource with HTTPS
        stub_request(:get, "https://google.golang.org/api?go-get=1")
          .to_return(
            status: 200,
            body: <<~HTML
              <html>
              <head>
                <meta name="go-import" content="google.golang.org/api git https://go.googlesource.com/api">
              </head>
              </html>
            HTML
          )

        # Mock enterprise vanity import -> internal GitLab with SSH
        stub_request(:get, "https://code.enterprise.com/platform/auth?go-get=1")
          .to_return(
            status: 200,
            body: <<~HTML
              <html>
              <head>
                <meta name="go-import" content="code.enterprise.com/platform/auth git ssh://git@gitlab.enterprise.com/platform/auth">
              </head>
              </html>
            HTML
          )
      end

      it "identifies vanity import dependencies correctly" do
        vanity_deps = resolver.vanity_dependencies
        expect(vanity_deps.map(&:name)).to contain_exactly(
          "k8s.io/client-go",
          "google.golang.org/api", 
          "code.enterprise.com/platform/auth"
        )
      end

      it "resolves git hosts from vanity import meta tags" do
        git_hosts = resolver.resolve_git_hosts
        
        # Should extract git hosts from SSH and HTTPS URLs
        hosts = git_hosts.map { |entry| entry[:git] }
        expect(hosts).to include("github.com/kubernetes/client-go")
        expect(hosts).to include("go.googlesource.com/api")
        expect(hosts).to include("gitlab.enterprise.com/platform/auth")
      end

      it "handles mixed SSH and HTTPS git URLs correctly" do
        git_hosts = resolver.resolve_git_hosts
        
        # Should work with both SSH (github.com/kubernetes/client-go) and HTTPS formats
        k8s_entry = git_hosts.find { |entry| entry[:vanity] == "k8s.io/client-go" }
        expect(k8s_entry[:git]).to eq("github.com/kubernetes/client-go")
        
        google_entry = git_hosts.find { |entry| entry[:vanity] == "google.golang.org/api" }
        expect(google_entry[:git]).to eq("go.googlesource.com/api")
        
        enterprise_entry = git_hosts.find { |entry| entry[:vanity] == "code.enterprise.com/platform/auth" }
        expect(enterprise_entry[:git]).to eq("gitlab.enterprise.com/platform/auth")
      end

      context "when vanity import resolution fails (network issues)" do
        before do
          # Simulate network timeout for one vanity import
          stub_request(:get, "https://k8s.io/client-go?go-get=1")
            .to_timeout
        end

        it "falls back to prediction and continues processing other imports" do
          git_hosts = resolver.resolve_git_hosts
          
          # Should predict k8s.io -> github.com mapping and still process others
          predicted_hosts = git_hosts.select { |entry| entry[:vanity] == "k8s.io/client-go" }
          expect(predicted_hosts).not_to be_empty
          
          # Should still resolve other working vanity imports
          google_entry = git_hosts.find { |entry| entry[:vanity] == "google.golang.org/api" }
          expect(google_entry).not_to be_nil
        end
      end

      context "when vanity import returns malformed HTML" do
        before do
          stub_request(:get, "https://code.enterprise.com/platform/auth?go-get=1")
            .to_return(
              status: 200,
              body: "<html><body>Not a valid go-import page</body></html>"
            )
        end

        it "falls back to prediction for malformed responses" do
          git_hosts = resolver.resolve_git_hosts
          
          # Should predict based on domain pattern
          enterprise_entries = git_hosts.select { |entry| entry[:vanity] == "code.enterprise.com/platform/auth" }
          expect(enterprise_entries).not_to be_empty
          
          # Should still resolve working vanity imports
          k8s_entry = git_hosts.find { |entry| entry[:vanity] == "k8s.io/client-go" }
          expect(k8s_entry).not_to be_nil
        end
      end
    end

    context "SSH URL vanity import scenario" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "internal.company.com/shared/logger",
            version: "v1.0.0",
            requirements: [],
            package_manager: "go_modules"
          )
        ]
      end

      before do
        # Mock vanity import response with SSH URL
        stub_request(:get, "https://internal.company.com/shared/logger?go-get=1")
          .to_return(
            status: 200,
            body: <<~HTML
              <html>
              <head>
                <meta name="go-import" content="internal.company.com/shared/logger git ssh://git@git.company.com/shared/logger.git">
              </head>
              </html>
            HTML
          )
      end

      it "extracts git host from SSH URL for git rewrite rules" do
        git_hosts = resolver.resolve_git_hosts
        
        expect(git_hosts).to have(1).item
        expect(git_hosts.first[:vanity]).to eq("internal.company.com/shared/logger")
        expect(git_hosts.first[:git]).to eq("git.company.com/shared/logger.git")
      end

      it "enables proper git configuration to convert SSH to HTTPS" do
        # This test verifies the extracted host can be used for git rewrite rules
        git_hosts = resolver.resolve_git_hosts
        git_host = git_hosts.first[:git]
        
        # The extracted host should be usable for SharedHelpers.configure_git_to_use_https
        expect(git_host).to match(/^git\.company\.com\//)
        expect(git_host).not_to include("ssh://")
        expect(git_host).not_to include("git@")
      end
    end
  end
end
