# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/hex/credential_helpers"
require "tmpdir"

RSpec.describe Dependabot::Hex::CredentialHelpers do
  extend T::Sig

  describe ".configure" do
    subject(:configure) { described_class.configure(credentials: credentials, env: env) }

    let(:credentials) { [] }
    let(:env) { { "HEX_HOME" => "/tmp/hex-home", "MIX_QUIET" => "1" } }
    let(:public_key) do
      <<~PEM
        -----BEGIN PUBLIC KEY-----
        MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEApqREcFDt5vV21JVe2QNB
        Edvzk6w36aNFhVGWN5toNJRjRJ6m4hIuG4KaXtDWVLjnvct6MYMfqhC79HAGwyF+
        IqR6Q6a5bbFSsImgBJwz1oadoVKD6ZNetAuCIK84cjMrEFRkELtEIPNHblCzUkkM
        3rS9+DPlnfG8hBvGi6tvQIuZmXGCxF/73hU0/MyGhbmEjIKRtG6b0sJYKelRLTPW
        XgK7s5pESgiwf2YC/2MGDXjAJfpfCd0RpLdvd4eRiXtVlE9qO9bND94E7PgQ/xqZ
        J1i2xWFndWa6nfFnRxZmCStCOZWYYPlaxr+FZceFbpMwzTNs4g3d4tLNUcbKAIH4
        0wIDAQAB
        -----END PUBLIC KEY-----
      PEM
    end
    let(:public_key_fingerprint) { "SHA256:O1LOYhHFW4kcrblKAxROaDEzLD8bn1seWbe5tq8TRsk" }
    let(:organization_token) { "organization-secret-token" }
    let(:organization_credentials) do
      [
        Dependabot::Credential.new(
          {
            "type" => "hex_organization",
            "organization" => "dependabot",
            "token" => organization_token
          }
        )
      ]
    end
    let(:organization_authentication_error) do
      Dependabot::SharedHelpers::HelperSubprocessFailed.new(
        message: "Failed to authenticate against organization repository with given key because of: Forbidden",
        error_context: {}
      )
    end

    shared_context "with a real credential helper" do
      let(:hex_home) { Dir.mktmpdir("dependabot-hex-home") }
      let(:env) { { "HEX_HOME" => hex_home, "MIX_EXS" => "mix.exs", "MIX_QUIET" => "1" } }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
      end

      after do
        FileUtils.rm_rf(hex_home)
      end
    end

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("")
    end

    context "with an organization token" do
      let(:credentials) { organization_credentials }

      it "uses the public organization task without exposing the token" do
        configure

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
          array_including("lib/configure_credentials.exs", "--", "organization", "dependabot"),
          hash_including(
            cwd: Dependabot::Hex::NativeHelpers.hex_helpers_dir,
            env: env.merge(
              "DEPENDABOT_HEX_CREDENTIAL_TOKEN" => "organization-secret-token",
              "MIX_BUILD_PATH" => "/tmp/hex-home/build"
            ),
            fingerprint: "mix run configure_credentials.exs organization <organization>"
          )
        )
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command) do |command, options|
          expect(command).not_to include("organization-secret-token")
          expect(options.fetch(:fingerprint)).not_to include("organization-secret-token")
        end
      end
    end

    context "with organization and explicit repository credentials" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "hexpm:first",
              "url" => "https://first.example.com",
              "public-key" => public_key
            }
          ),
          organization_credentials.first,
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "hexpm:second",
              "url" => "https://second.example.com",
              "public-key" => public_key
            }
          ),
          Dependabot::Credential.new(
            {
              "type" => "hex_organization",
              "organization" => "second",
              "token" => "second-secret-token"
            }
          )
        ]
      end

      it "applies organizations first while preserving order within each group" do
        configure

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          .with(array_including("--", "organization", "dependabot"), anything).ordered
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          .with(array_including("--", "organization", "second"), anything).ordered
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          .with(array_including("--", "repository", "hexpm:first"), anything).ordered
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          .with(array_including("--", "repository", "hexpm:second"), anything).ordered
      end
    end

    context "with tokenless organization metadata" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_organization",
              "token" => ""
            }
          )
        ]
      end

      it "does not perform setup" do
        configure

        expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
      end
    end

    context "when the organization token is rejected remotely" do
      let(:credentials) { organization_credentials }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_raise(organization_authentication_error)
      end

      it "fails immediately with a clear authentication error" do
        expect { configure }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
            expect(error.source).to eq("dependabot")
            expect(error.cause).to be_nil
            expect(error.full_message).not_to include(organization_token)
          end
      end
    end

    context "when organization setup fails internally" do
      let(:credentials) { organization_credentials }
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Failed to verify authentication key",
          error_context: {}
        )
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_raise(error)
      end

      it "re-raises the original failure unchanged" do
        expect { configure }.to raise_error do |raised_error|
          expect(raised_error).to equal(error)
        end
      end
    end

    context "with fingerprint-only repository credentials" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "dependabot",
              "url" => "https://repo.example.com",
              "auth-key" => "repository-secret-key",
              "public-key-fingerprint" => public_key_fingerprint
            }
          )
        ]
      end

      it "delegates key fetching and verification to the public repository task" do
        configure

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
          array_including(
            "lib/configure_credentials.exs",
            "--",
            "repository",
            "dependabot",
            public_key_fingerprint
          ),
          hash_including(
            env: env.merge(
              "DEPENDABOT_HEX_CREDENTIAL_TOKEN" => "repository-secret-key",
              "DEPENDABOT_HEX_PUBLIC_KEY" => "",
              "DEPENDABOT_HEX_REPOSITORY_URL_TOKEN" => "https://repo.example.com",
              "MIX_BUILD_PATH" => "/tmp/hex-home/build"
            ),
            fingerprint: "mix run configure_credentials.exs repository <repository>"
          )
        )
      end
    end

    context "when repository public key authentication fails" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "dependabot",
              "url" => "https://repo.example.com",
              "public-key-fingerprint" => public_key_fingerprint
            }
          )
        ]
      end
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Downloading public key failed with code \"401\"\n",
          error_context: {}
        )
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_raise(error)
      end

      it "reports authentication failure for the repository" do
        expect { configure }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |raised_error|
            expect(raised_error.source).to eq("dependabot")
          end
      end
    end

    context "when repository public key download fails for another reason" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "dependabot",
              "url" => "https://repo.example.com",
              "public-key-fingerprint" => public_key_fingerprint
            }
          )
        ]
      end
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Downloading public key failed with code \"500\"\n",
          error_context: {}
        )
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_raise(error)
      end

      it "re-raises the original failure unchanged" do
        expect { configure }.to raise_error do |raised_error|
          expect(raised_error).to equal(error)
        end
      end
    end

    context "with a supplied repository public key" do
      include_context "with a real credential helper"
      let(:repository_name) { "dependabot" }
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => repository_name,
              "url" => "https://repo.example.com",
              "public-key" => public_key
            }
          )
        ]
      end

      it "installs the supplied key without fetching one" do
        configure

        fingerprint = Dependabot::SharedHelpers.run_shell_command(
          ["mix", "hex.repo", "show", repository_name, "--public-key"],
          cwd: Dependabot::Hex::NativeHelpers.hex_helpers_dir,
          env: { "HEX_HOME" => hex_home }
        )

        expect(fingerprint.strip).to eq(public_key.strip)
      end

      context "when the repository is named hexpm" do
        let(:repository_name) { "hexpm" }

        it "disables OAuth exchange" do
          configure

          expect(File.read(File.join(hex_home, "hex.config"))).to include("oauth_exchange => false")
        end
      end
    end

    context "with a repository auth key that begins with dashes" do
      include_context "with a real credential helper"
      let(:repository_auth_key) { "--repository-secret-key" }
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "dependabot",
              "url" => "https://repo.example.com",
              "auth-key" => repository_auth_key,
              "public-key" => public_key
            }
          )
        ]
      end

      it "treats the key as an option value without exposing it in the subprocess invocation" do
        expect { configure }.not_to raise_error

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command) do |command, options|
          expect(command).not_to include(repository_auth_key)
          expect(options.fetch(:fingerprint)).not_to include(repository_auth_key)
        end
      end
    end

    context "with matching repository public key and fingerprint" do
      include_context "with a real credential helper"
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "dependabot",
              "url" => "https://repo.example.com",
              "public-key" => public_key,
              "public-key-fingerprint" => public_key_fingerprint
            }
          )
        ]
      end

      it "verifies and installs the supplied key" do
        expect { configure }.not_to raise_error
      end
    end

    context "with mismatched repository public key and fingerprint" do
      include_context "with a real credential helper"
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "dependabot",
              "url" => "https://repo.example.com",
              "public-key" => public_key,
              "public-key-fingerprint" => "SHA256:incorrect"
            }
          )
        ]
      end

      it "fails with the repository name" do
        expect { configure }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed) do |error|
            expect(error.message).to include('Public key fingerprint mismatch for repo "dependabot"')
          end
      end
    end

    context "with undecodable repository public keys and a fingerprint" do
      include_context "with a real credential helper"

      it "reports sanitized repository-specific errors" do
        [
          %w(malformed-public-key-secret malformed-public-key-secret),
          [public_key + public_key, public_key.lines[1].strip]
        ].each do |supplied_public_key, secret_fragment|
          repository_credentials = [
            Dependabot::Credential.new(
              {
                "type" => "hex_repository",
                "repo" => "dependabot",
                "url" => "https://repo.example.com",
                "public-key" => supplied_public_key,
                "public-key-fingerprint" => public_key_fingerprint
              }
            )
          ]

          expect { described_class.configure(credentials: repository_credentials, env: env) }
            .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed) do |error|
              expect(error.message).to include('Could not decode public key for repo "dependabot"')
              expect(error.message).not_to include(secret_fragment)
            end
        end
      end
    end

    context "with a malformed repository public key" do
      include_context "with a real credential helper"
      let(:malformed_public_key) { "malformed-public-key-secret" }
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "dependabot",
              "url" => "https://repo.example.com",
              "public-key" => malformed_public_key
            }
          )
        ]
      end

      it "reports a sanitized repository-specific error" do
        expect { configure }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed) do |error|
            expect(error.message).to include('Could not decode public key for repo "dependabot"')
            expect(error.message).not_to include(malformed_public_key)
          end
      end
    end

    context "without a repository public key or fingerprint" do
      include_context "with a real credential helper"
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "dependabot",
              "url" => "https://repo.example.com"
            }
          )
        ]
      end

      it "fails with an actionable configuration error before invoking Mix" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)

        expect { configure }
          .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to eq(
              'Hex repository "dependabot" must provide either `public-key` or ' \
              "`public-key-fingerprint` in dependabot.yml"
            )
          end
        expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
      end
    end

    context "when setup output includes repository URL query secrets" do
      let(:repository_url) do
        "https://repo.example.com/über path?access_token=secret%2Bvalue&region=west&empty=#fragment"
      end
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "dependabot",
              "url" => repository_url,
              "public-key" => public_key
            }
          )
        ]
      end
      let(:error_context) { { command: "mix run configure_credentials.exs" } }
      let(:trace) { ["helper trace"] }
      let(:error_cause) { RuntimeError.new("Request failed for #{repository_url}") }
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Request failed for #{repository_url}",
          error_context: error_context,
          trace: trace
        )
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do
          raise error, cause: error_cause
        end
      end

      it "redacts every non-empty query value while preserving diagnostic context" do
        expect { configure }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed) do |sanitized_error|
            expect(sanitized_error.message).to include(
              "https://repo.example.com/über path?access_token=***&region=***&empty=#fragment"
            )
            expect(sanitized_error.message).not_to include("secret%2Bvalue")
            expect(sanitized_error.full_message).not_to include("secret%2Bvalue")
            expect(sanitized_error.cause).to be_nil
            expect(sanitized_error.error_context).to eq(error_context)
            expect(sanitized_error.trace).to eq(trace)
          end
      end
    end

    context "when setup output includes an invalid UTF-8 query value" do
      let(:repository_url) { "https://repo.example.com/private?access_token=secret%FF" }
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "dependabot",
              "url" => repository_url,
              "public-key" => public_key
            }
          )
        ]
      end
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Request failed for #{repository_url}",
          error_context: {}
        )
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do
          raise error, cause: RuntimeError.new("Request failed for #{repository_url}")
        end
      end

      it "redacts the raw value without retaining an unsanitized cause" do
        expect { configure }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed) do |sanitized_error|
            expect(sanitized_error.full_message).to include("access_token=***")
            expect(sanitized_error.full_message).not_to include("secret%FF")
            expect(sanitized_error.cause).to be_nil
          end
      end
    end

    context "with a secret-bearing repository URL" do
      let(:repository_url) do
        "https://url-user:url-password@repo.example.com/private?access_token=url-query-secret"
      end
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "dependabot",
              "url" => repository_url,
              "public-key" => public_key
            }
          )
        ]
      end
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "credential configuration failed",
          error_context: {}
        )
      end
      let(:invocation) { {} }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |command, **options|
          invocation[:command] = command
          invocation[:options] = options
          raise error
        end
      end

      it "keeps URL credentials out of diagnostics and re-raises the original failure" do
        expect { configure }.to raise_error do |raised_error|
          expect(raised_error).to equal(error)
          expect([raised_error.message, raised_error.error_context.inspect].join("\n")).not_to include(repository_url)
        end

        expect(invocation.fetch(:command)).not_to include(repository_url)
        expect(invocation.fetch(:options).fetch(:fingerprint)).not_to include(repository_url)
        expect(invocation.fetch(:options).fetch(:env)).to include(
          "DEPENDABOT_HEX_REPOSITORY_URL_TOKEN" => repository_url
        )
      end
    end
  end

  describe ".sanitize_error" do
    let(:repository_url) do
      "https://repo.example.com?first=alpha&second=betaSECRET&first=alpha%26second%3Dbeta"
    end
    let(:credentials) do
      [Dependabot::Credential.new({ "type" => "hex_repository", "url" => repository_url })]
    end
    let(:error) do
      Dependabot::SharedHelpers::HelperSubprocessFailed.new(
        message: "Failed: #{repository_url}",
        error_context: {}
      )
    end

    it "fully redacts overlapping raw and encoded query pairs" do
      sanitized_error = described_class.sanitize_error(error: error, credentials: credentials)

      expect(sanitized_error.message).to include("https://repo.example.com?first=***&second=***&first=***")
      expect(sanitized_error.message).not_to include("alpha", "betaSECRET", "alpha%26second%3Dbeta")
    end
  end

  describe ".authentication_source" do
    it "matches only complete supported authentication diagnostics" do
      {
        "No authenticated organization found for hexpm:my-org2/example.repo." =>
          "hexpm:my-org2/example.repo",
        "** (Mix) No authenticated organization found for my_org.\n" => "my_org",
        "No authenticated organization found for my-org. Do you want to authenticate it now? [Yn]   " => "my-org",
        'Missing credentials for "hexpm:my-org2/example.repo"' => "hexpm:my-org2/example.repo",
        'Downloading public key for repo "my-org" failed with code: 401' => "my-org"
      }.each do |message, source|
        expect(described_class.authentication_source(message)).to eq(source)
      end
    end

    it "rejects embedded, malformed, and ambiguous diagnostics" do
      [
        "prefix No authenticated organization found for my-org.",
        "No authenticated organization found for bad\"name.",
        "No authenticated organization found for bad\nname.",
        "No authenticated organization found for my-org. unexpected suffix",
        "Missing credentials for \"my-org\"\n",
        'Public key fingerprint mismatch for repo "my-org"',
        "Failed to fetch record for my-org"
      ].each do |message|
        expect(described_class.authentication_source(message)).to be_nil
      end
    end
  end

  describe ".organization_credentials" do
    subject(:organization_credentials) { described_class.organization_credentials(credentials) }

    sig { returns(T::Array[Dependabot::Credential]) }
    let(:credentials) do
      [
        Dependabot::Credential.new(
          { "type" => "hex_organization", "organization" => "organization",
            "token" => "token" }
        )
      ]
    end

    it "populates the credentials with default properties" do
      expect(organization_credentials).to eq(%w(hex_organization organization token))
    end
  end

  describe ".repo_credentials" do
    subject(:repo_credentials) { described_class.repo_credentials(credentials) }

    sig { returns(T::Array[Dependabot::Credential]) }
    let(:credentials) do
      [
        Dependabot::Credential.new(
          { "type" => "hex_repository", "url" => "url", "auth_key" => "auth_key",
            "public_key_fingerprint" => "public_key_fingerprint" }
        )
      ]
    end

    it "populates the credentials with default properties" do
      expect(repo_credentials).to eq(["hex_repository", "url", "auth_key", "public_key_fingerprint", ""])
    end

    context "with a public key" do
      sig { returns(T::Array[Dependabot::Credential]) }
      let(:credentials) do
        [
          Dependabot::Credential.new(
            { "type" => "hex_repository", "repo" => "repo", "url" => "url", "public_key" => "public_key" }
          )
        ]
      end

      it "includes the public key" do
        expect(repo_credentials).to eq(%w(hex_repository repo url) + ["", "", "public_key"])
      end
    end

    context "with keys spelled as in dependabot.yml" do
      sig { returns(T::Array[Dependabot::Credential]) }
      let(:credentials) do
        [
          Dependabot::Credential.new(
            { "type" => "hex_repository", "repo" => "repo", "url" => "url", "auth-key" => "auth_key",
              "public-key-fingerprint" => "public_key_fingerprint", "public-key" => "public_key" }
          )
        ]
      end

      it "reads them" do
        expect(repo_credentials).to eq(%w(hex_repository repo url auth_key public_key_fingerprint public_key))
      end
    end
  end
end
