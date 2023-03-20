# frozen_string_literal: true

require "spec_helper"
require "dependabot/hex/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Hex::FileFetcher do
  it_behaves_like "a dependency file fetcher"

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }
  let(:json_header) { { "content-type" => "application/json" } }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }

  before do
    stub_request(:get, url + "?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "contents_elixir.json"),
        headers: json_header
      )

    stub_request(:get, url + "mix.exs?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "contents_elixir_mixfile.json"),
        headers: json_header
      )

    stub_request(:get, url + "mix.lock?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "contents_elixir_lockfile.json"),
        headers: json_header
      )
  end

  it "fetches the mix.exs and mix.lock" do
    expect(file_fetcher_instance.files.count).to eq(2)
    expect(file_fetcher_instance.files.map(&:name)).
      to match_array(%w(mix.exs mix.lock))
  end

  context "without a lockfile" do
    before do
      stub_request(:get, url + "mix.lock?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404, headers: json_header)
    end

    it "fetches the mix.exs" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(mix.exs))
    end
  end

  context "with an evaled file" do
    before do
      stub_request(:get, url + "mix.exs?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body:
            fixture("github", "contents_elixir_mixfile_with_eval_file.json"),
          headers: json_header
        )
      stub_request(:get, url + "version?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body:
            fixture("github", "contents_todo_txt.json"),
          headers: json_header
        )
    end

    it "fetches the evaled file" do
      expect(file_fetcher_instance.files.count).to eq(3)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(mix.exs mix.lock version))
    end
  end

  context "with an evaled file without a relative directory" do
    before do
      stub_request(:get, url + "mix.exs?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body:
            fixture("github", "contents_elixir_mixfile_with_eval_file_without_relative_dir.json"),
          headers: json_header
        )
      stub_request(:get, url + "version?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body:
            fixture("github", "contents_todo_txt.json"),
          headers: json_header
        )
    end

    it "fetches the evaled file" do
      expect(file_fetcher_instance.files.count).to eq(3)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(mix.exs mix.lock version))
    end
  end

  context "with a required file" do
    before do
      stub_request(:get, url + "mix.exs?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body:
            fixture("github", "contents_elixir_mixfile_with_require_file.json"),
          headers: json_header
        )
      stub_request(:get, url + "rel/releases.ex?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body:
            fixture("github", "contents_todo_txt.json"),
          headers: json_header
        )
    end

    it "fetches the required file" do
      expect(file_fetcher_instance.files.count).to eq(3)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(mix.exs mix.lock rel/releases.ex))
    end
  end

  context "with a required file without a relative directory" do
    before do
      stub_request(:get, url + "mix.exs?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body:
            fixture("github", "contents_elixir_mixfile_with_require_file_without_relative_dir.json"),
          headers: json_header
        )
      stub_request(:get, url + "rel/releases.ex?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body:
            fixture("github", "contents_todo_txt.json"),
          headers: json_header
        )
    end

    it "fetches the required file" do
      expect(file_fetcher_instance.files.count).to eq(3)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(mix.exs mix.lock rel/releases.ex))
    end
  end

  context "with an umbrella app" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_elixir_umbrella.json"),
          headers: json_header
        )

      stub_request(:get, url + "mix.exs?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_elixir_umbrella_mixfile.json"),
          headers: json_header
        )

      stub_request(:get, url + "apps?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_elixir_umbrella_apps.json"),
          headers: json_header
        )

      stub_request(:get, url + "apps/bank/mix.exs?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_elixir_bank_mixfile.json"),
          headers: json_header
        )
      stub_request(:get, url + "apps/bank_web/mix.exs?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_elixir_bank_web_mixfile.json"),
          headers: json_header
        )
    end

    it "fetches the mixfiles for the sub-apps" do
      expect(file_fetcher_instance.files.count).to eq(4)
      expect(file_fetcher_instance.files.map(&:name)).
        to include("apps/bank/mix.exs")
    end

    context "when one of the folders isn't an app" do
      before do
        stub_request(:get, url + "apps/bank_web/mix.exs?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 404,
            headers: json_header
          )
      end

      it "fetches the mixfiles for the other sub-apps" do
        expect(file_fetcher_instance.files.count).to eq(3)
        expect(file_fetcher_instance.files.map(&:name)).
          to include("apps/bank/mix.exs")
        expect(file_fetcher_instance.files.map(&:name)).
          to_not include("apps/bank_web/mix.exs")
      end
    end

    context "when one of apps evals a top level file" do
      before do
        stub_request(:get, url + "apps/bank_web/mix.exs?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "contents_elixir_bank_web_mixfile_with_eval.json"),
            headers: json_header
          )

        stub_request(:get, url + "evaled.exs?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body:
              fixture("github", "contents_todo_txt.json"),
            headers: json_header
          )
      end

      it "fetches the evaled file" do
        expect(file_fetcher_instance.files.count).to eq(5)
        expect(file_fetcher_instance.files.map(&:name)).
          to include("evaled.exs")
      end
    end

    context "when the apps folder doesn't exist" do
      before do
        stub_request(:get, url + "apps?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 404,
            headers: json_header
          )
      end

      it "ignores the apps_path declaration" do
        expect(file_fetcher_instance.files.count).to eq(2)
        expect(file_fetcher_instance.files.map(&:name)).
          to eq(%w(mix.exs mix.lock))
      end
    end
  end

  context "with an umbrella app in a directory" do
    let(:source) do
      Dependabot::Source.new(
        provider: "github",
        repo: "gocardless/bump",
        directory: "api"
      )
    end

    before do
      stub_request(:get, url + "api?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_elixir_umbrella.json"),
          headers: json_header
        )

      stub_request(:get, url + "api/mix.exs?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_elixir_umbrella_mixfile.json"),
          headers: json_header
        )

      stub_request(:get, url + "api/mix.lock?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_elixir_lockfile.json"),
          headers: json_header
        )

      stub_request(:get, url + "api/apps?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_elixir_umbrella_api_apps.json"),
          headers: json_header
        )

      stub_request(:get, url + "api/apps/bank/mix.exs?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_elixir_bank_mixfile.json"),
          headers: json_header
        )

      stub_request(:get, url + "api/apps/bank_web/mix.exs?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_elixir_bank_web_mixfile.json"),
          headers: json_header
        )
    end

    it "fetches the mixfiles for nested sub-apps" do
      expect(file_fetcher_instance.files.count).to eq(4)
      expect(file_fetcher_instance.files.map(&:name)).
        to include("apps/bank/mix.exs")
    end
  end

  context "with sub-projects" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_elixir_umbrella.json"),
          headers: json_header
        )

      stub_request(:get, url + "mix.exs?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_elixir_sub_project_mixfile.json"),
          headers: json_header
        )

      stub_request(:get, url + "apps?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_elixir_umbrella_apps.json"),
          headers: json_header
        )

      stub_request(:get, url + "apps/bank/mix.exs?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_elixir_bank_mixfile.json"),
          headers: json_header
        )
    end

    it "fetches the mixfiles for the sub-apps" do
      expect(file_fetcher_instance.files.count).to eq(3)
      expect(file_fetcher_instance.files.map(&:name)).
        to include("apps/bank/mix.exs")
    end
  end
end
