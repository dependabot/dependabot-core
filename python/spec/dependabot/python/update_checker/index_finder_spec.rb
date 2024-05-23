# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/python/update_checker/index_finder"

RSpec.describe Dependabot::Python::UpdateChecker::IndexFinder do
  let(:finder) do
    described_class.new(
      dependency_files: dependency_files,
      credentials: credentials,
      dependency: dependency
    )
  end
  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    })]
  end
  let(:dependency_files) { [requirements_file] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "requests",
      version: "2.4.1",
      requirements: [{
        requirement: "==2.4.1",
        file: "requirements.txt",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "pip"
    )
  end

  before do
    stub_request(:get, pypi_url).to_return(status: 200, body: pypi_response)
  end

  let(:pypi_url) { "https://pypi.org/simple/luigi/" }
  let(:pypi_response) { fixture("pypi", "pypi_simple_response.html") }

  let(:pipfile) do
    Dependabot::DependencyFile.new(
      name: "Pipfile",
      content: fixture("pipfile_files", pipfile_fixture_name)
    )
  end
  let(:pipfile_fixture_name) { "exact_version" }
  let(:pyproject) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: fixture("pyproject_files", pyproject_fixture_name)
    )
  end
  let(:pyproject_fixture_name) { "poetry_exact_requirement.toml" }
  let(:requirements_file) do
    Dependabot::DependencyFile.new(
      name: "requirements.txt",
      content: fixture("requirements", requirements_fixture_name)
    )
  end
  let(:requirements_fixture_name) { "version_specified.txt" }
  let(:pip_conf) do
    Dependabot::DependencyFile.new(
      name: "pip.conf",
      content: fixture("pip_conf_files", pip_conf_fixture_name)
    )
  end
  let(:pip_conf_fixture_name) { "custom_index" }

  describe "#index_urls" do
    subject(:index_urls) { finder.index_urls }

    context "without any additional indexes specified" do
      it { is_expected.to eq(["https://pypi.org/simple/"]) }
    end

    context "with a custom index-url" do
      let(:pypi_url) do
        "https://pypi.weasyldev.com/weasyl/source/+simple/luigi/"
      end

      context "when setting in a pip.conf file" do
        let(:pip_conf_fixture_name) { "custom_index" }
        let(:dependency_files) { [pip_conf] }

        it "gets the right index URL" do
          expect(index_urls)
            .to eq(["https://pypi.weasyldev.com/weasyl/source/+simple/"])
        end
      end

      context "when setting in a requirements.txt file" do
        let(:requirements_fixture_name) { "custom_index.txt" }
        let(:dependency_files) { [requirements_file] }

        it "gets the right index URL" do
          expect(index_urls)
            .to eq(["https://pypi.weasyldev.com/weasyl/source/+simple/"])
        end

        context "with quotes" do
          let(:requirements_fixture_name) { "custom_index_quotes.txt" }
          let(:dependency_files) { [requirements_file] }

          it "gets the right index URL" do
            expect(index_urls)
              .to eq(["https://pypi.weasyldev.com/weasyl/source/+simple/"])
          end
        end
      end

      context "when setting in a Pipfile" do
        let(:pipfile_fixture_name) { "private_source" }
        let(:dependency_files) { [pipfile] }

        it { is_expected.to eq(["https://some.internal.registry.com/pypi/"]) }

        context "when unparseable" do
          let(:pipfile_fixture_name) { "unparseable" }

          it { is_expected.to eq(["https://pypi.org/simple/"]) }
        end
      end

      context "when setting in a pyproject.toml" do
        let(:pyproject_fixture_name) { "private_source.toml" }
        let(:dependency_files) { [pyproject] }

        it { is_expected.to eq(["https://some.internal.registry.com/pypi/"]) }

        context "when unparseable" do
          let(:pyproject_fixture_name) { "unparseable.toml" }

          it { is_expected.to eq(["https://pypi.org/simple/"]) }
        end
      end

      context "when pypi explicitly set in a pyproject.toml" do
        let(:pyproject_fixture_name) { "pypi_explicit.toml" }
        let(:dependency_files) { [pyproject] }

        it { is_expected.to eq(["https://pypi.org/simple/"]) }
      end

      context "when pypi explicitly set in a pyproject.toml, in lowercase" do
        let(:pyproject_fixture_name) { "pypi_explicit_lowercase.toml" }
        let(:dependency_files) { [pyproject] }

        it { is_expected.to eq(["https://pypi.org/simple/"]) }
      end

      context "when setting in credentials" do
        let(:credentials) do
          [Dependabot::Credential.new({
            "type" => "python_index",
            "index-url" => "https://pypi.weasyldev.com/weasyl/source/+simple",
            "replaces-base" => true
          })]
        end

        it "gets the right index URL" do
          expect(index_urls)
            .to eq(["https://pypi.weasyldev.com/weasyl/source/+simple/"])
        end

        context "with credentials passed as a token" do
          let(:credentials) do
            [Dependabot::Credential.new({
              "type" => "python_index",
              "index-url" => "https://pypi.weasyldev.com/weasyl/source/+simple",
              "token" => "user:pass",
              "replaces-base" => true
            })]
          end

          it "gets the right index URL" do
            expect(index_urls)
              .to eq(
                ["https://user:pass@pypi.weasyldev.com/weasyl/source/+simple/"]
              )
          end
        end
      end
    end

    context "with an extra-index-url" do
      context "when setting in a pip.conf file" do
        let(:pip_conf_fixture_name) { "extra_index" }
        let(:dependency_files) { [pip_conf] }

        it "gets the right index URLs" do
          expect(index_urls).to contain_exactly("https://pypi.org/simple/", "https://pypi.weasyldev.com/weasyl/source/+simple/")
        end

        context "when including an environment variables" do
          let(:pip_conf_fixture_name) { "extra_index_env_variable" }

          it "raises a helpful error" do
            error_class = Dependabot::PrivateSourceAuthenticationFailure
            expect { index_urls }
              .to raise_error(error_class) do |error|
                expect(error.source)
                  .to eq("https://pypi.weasyldev.com/${SECURE_NAME}" \
                         "/source/+simple/")
              end
          end

          context "when provided as a config variable" do
            let(:credentials) do
              [Dependabot::Credential.new({
                "type" => "python_index",
                "index-url" => "https://pypi.weasyldev.com/weasyl/" \
                               "source/+simple",
                "replaces-base" => false
              })]
            end

            it "gets the right index URLs" do
              expect(index_urls).to contain_exactly("https://pypi.org/simple/", "https://pypi.weasyldev.com/weasyl/source/+simple/")
            end

            context "with a gemfury style" do
              let(:credentials) do
                [Dependabot::Credential.new({
                  "type" => "python_index",
                  "index-url" => "https://pypi.weasyldev.com/source/+simple"
                })]
              end
              let(:url) { "https://pypi.weasyldev.com/source/+simple/luigi/" }

              it "gets the right index URLs" do
                expect(index_urls).to contain_exactly("https://pypi.org/simple/", "https://pypi.weasyldev.com/source/+simple/")
              end
            end

            context "when the env variable is for basic auth details" do
              let(:pip_conf_fixture_name) do
                "extra_index_env_variable_basic_auth"
              end

              let(:credentials) do
                [Dependabot::Credential.new({
                  "type" => "python_index",
                  "index-url" => "https://pypi.weasyldev.com/source/+simple",
                  "token" => "user:pass",
                  "replaces-base" => false
                })]
              end

              it "gets the right index URLs" do
                expect(index_urls).to contain_exactly("https://pypi.org/simple/", "https://user:pass@pypi.weasyldev.com/source/+simple/")
              end
            end
          end
        end
      end

      context "when setting in a requirements.txt file" do
        let(:requirements_fixture_name) { "extra_index.txt" }
        let(:dependency_files) { [requirements_file] }

        it "gets the right index URLs" do
          expect(index_urls).to contain_exactly("https://pypi.org/simple/", "https://pypi.weasyldev.com/weasyl/source/+simple/")
        end

        context "with quotes" do
          let(:requirements_fixture_name) { "extra_index_quotes.txt" }

          it "gets the right index URLs" do
            expect(index_urls).to contain_exactly("https://pypi.org/simple/", "https://cakebot.mycloudrepo.io/public/repositories/py/")
          end
        end
      end

      context "when setting in a pyproject.toml file" do
        let(:pyproject_fixture_name) { "extra_source.toml" }
        let(:dependency_files) { [pyproject] }

        it "gets the right index URLs" do
          expect(index_urls).to contain_exactly("https://pypi.org/simple/", "https://some.internal.registry.com/pypi/")
        end
      end

      context "when set in a pyproject.toml file and marked as explicit" do
        let(:pyproject_fixture_name) { "extra_source_explicit.toml" }
        let(:dependency_files) { [pyproject] }

        it "gets the right index URLs" do
          expect(index_urls).to contain_exactly("https://pypi.org/simple/")
        end
      end

      context "when set in a pyproject.toml file and marked as explicit and specify with source" do
        let(:pyproject_fixture_name) { "extra_source_explicit_and_package_specify_source.toml" }
        let(:dependency_files) { [pyproject] }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "requests",
            version: "2.4.1",
            requirements: [{
              requirement: "==2.4.1",
              file: "requirements.txt",
              groups: ["dependencies"],
              source: "custom"
            }],
            package_manager: "pip"
          )
        end

        it "gets the right index URLs" do
          expect(index_urls).to contain_exactly("https://some.internal.registry.com/pypi/")
        end
      end

      context "when setting in credentials" do
        let(:credentials) do
          [Dependabot::Credential.new({
            "type" => "python_index",
            "index-url" => "https://pypi.weasyldev.com/weasyl/source/+simple",
            "replaces-base" => false
          })]
        end

        it "gets the right index URLs" do
          expect(index_urls).to contain_exactly("https://pypi.org/simple/", "https://pypi.weasyldev.com/weasyl/source/+simple/")
        end
      end
    end
  end
end
