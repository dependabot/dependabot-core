# typed: false
# frozen_string_literal: true

require "dependabot/nuget/nuget_config_credential_helpers"

RSpec.describe Dependabot::Nuget::NuGetConfigCredentialHelpers do
  subject(:result) { user_nuget_config_contents_during_and_after_action }

  let(:user_nuget_config_contents_during_and_after_action) do
    path = Dependabot::Nuget::NuGetConfigCredentialHelpers.user_nuget_config_path
    content_during_action = nil
    Dependabot::Nuget::NuGetConfigCredentialHelpers.patch_nuget_config_for_action(credentials) do
      content_during_action = File.read(path)
    end
    content_after_action = File.read(path)
    { content_during_action: content_during_action, content_after_action: content_after_action }
  end

  let(:default_nuget_config_contents) do
    File.read(Dependabot::Nuget::NuGetConfigCredentialHelpers.user_nuget_config_path)
  end

  describe "user level NuGet.Config patching" do
    context "with an empty credential set" do
      let(:credentials) { [] }

      it "does not change the contents of the file" do
        expect(result[:content_during_action]).to eq(default_nuget_config_contents)
        expect(result[:content_after_action]).to eq(default_nuget_config_contents)
      end
    end

    context "with non-empty credential set" do
      let(:credentials) do
        [
          { "type" => "nuget_feed", "url" => "https://private.nuget.example.com/index.json",
            "token" => "secret_token" },
          { "type" => "nuget_feed", "url" => "https://public.nuget.example.com/index.json" },
          { "type" => "not_nuget", "some_other_field" => "some other value" }
        ]
      end

      context "with credentials given" do
        it "changes the content of the config file, then changes it back" do
          expect(result[:content_during_action]).to eq(
            <<~XML
              <?xml version="1.0" encoding="utf-8"?>
              <configuration>
                <packageSources>
                  <add key="nuget_source_1" value="https://private.nuget.example.com/index.json" />
                  <add key="nuget_source_2" value="https://public.nuget.example.com/index.json" />
                </packageSources>
                <packageSourceCredentials>
                  <nuget_source_1>
                    <add key="Username" value="user" />
                    <add key="ClearTextPassword" value="secret_token" />
                  </nuget_source_1>
                </packageSourceCredentials>
              </configuration>
            XML
          )
          expect(result[:content_after_action]).to eq(default_nuget_config_contents)
        end
      end

      context "when exception is raised" do
        it "restores the original file after an exception" do
          Dependabot::Nuget::NuGetConfigCredentialHelpers.patch_nuget_config_for_action(credentials) do
            raise "This exception was raised when the NuGet.Config file was patched"
          end
          nuget_config_content = File.read(Dependabot::Nuget::NuGetConfigCredentialHelpers.user_nuget_config_path)
          expect(nuget_config_content).to eq(default_nuget_config_contents)
        end
      end
    end
  end
end
