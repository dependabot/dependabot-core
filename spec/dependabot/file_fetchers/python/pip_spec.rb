# frozen_string_literal: true

require "dependabot/file_fetchers/python/pip"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::Python::Pip do
  it_behaves_like "a dependency file fetcher"

  describe ".required_files_in?" do
    subject { described_class.required_files_in?(filenames) }

    context "with only a requirements.txt" do
      let(:filenames) { %w(requirements.txt) }
      it { is_expected.to eq(true) }
    end

    context "with only a setup.py" do
      let(:filenames) { %w(setup.py) }
      it { is_expected.to eq(true) }
    end

    context "with only a requirements folder" do
      let(:filenames) { %w(requirements) }
      it { is_expected.to eq(true) }
    end

    context "with only a requirements-dev" do
      let(:filenames) { %w(requirements-dev.txt) }
      it { is_expected.to eq(true) }
    end

    context "with only a Pipfile and Pipfile.lock" do
      let(:filenames) { %w(Pipfile Pipfile.lock) }
      it { is_expected.to eq(true) }
    end

    context "with only a Pipfile" do
      let(:filenames) { %w(Pipfile) }
      it { is_expected.to eq(false) }
    end

    context "with a pyproject.toml" do
      let(:filenames) { %w(pyproject.toml) }
      it { is_expected.to eq(true) }
    end

    context "with no requirements" do
      let(:filenames) { %w(requirements-dev.md) }
      it { is_expected.to eq(false) }
    end
  end

  describe "#files" do
    let(:source) do
      Dependabot::Source.new(
        provider: "github",
        repo: "gocardless/bump",
        directory: directory
      )
    end
    let(:directory) { "/" }
    let(:file_fetcher_instance) do
      described_class.new(source: source, credentials: credentials)
    end
    let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }
    let(:credentials) do
      [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    end

    let(:json_header) { { "content-type" => "application/json" } }
    let(:repo_contents) do
      fixture("github", "contents_python_only_requirements.json")
    end

    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")

      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 200, body: repo_contents, headers: json_header)

      %w(app build_scripts data migrations tests).each do |dir|
        stub_request(:get, url + "#{dir}?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 200, body: "[]", headers: json_header)
      end

      stub_request(:get, url + "todo.txt?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_todo_txt.json"),
          headers: json_header
        )
    end

    context "with only a requirements.txt" do
      let(:repo_contents) do
        fixture("github", "contents_python_only_requirements.json")
      end

      before do
        stub_request(:get, url + "requirements.txt?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "requirements_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the requirements.txt file" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name)).
          to eq(["requirements.txt"])
      end

      context "and a todo.txt that is actually a requirements file" do
        before do
          stub_request(:get, url + "todo.txt?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "requirements_content.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches the unexpectedly named file" do
          expect(file_fetcher_instance.files.count).to eq(2)
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(todo.txt requirements.txt))
        end
      end
    end

    context "with only a setup.py file" do
      let(:repo_contents) do
        fixture("github", "contents_python_only_setup.json")
      end
      before do
        stub_request(:get, url + "setup.py?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "setup_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the setup.py file" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name)).
          to eq(["setup.py"])
      end
    end

    context "with only a Pipfile and Pipfile.lock" do
      let(:repo_contents) do
        fixture("github", "contents_python_only_pipfile_and_lockfile.json")
      end
      before do
        stub_request(:get, url + "Pipfile?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "setup_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end
      before do
        stub_request(:get, url + "Pipfile.lock?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "setup_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the Pipfile and lockfile" do
        expect(file_fetcher_instance.files.count).to eq(2)
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(Pipfile Pipfile.lock))
      end
    end

    context "with only a pyproject.toml" do
      let(:repo_contents) do
        fixture("github", "contents_python_only_pyproject.json")
      end
      before do
        stub_request(:get, url + "pyproject.toml?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "setup_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the pyproject.toml" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(pyproject.toml))
      end
    end

    context "with no setup.py, requirements.txt or Pipfile" do
      let(:repo_contents) { "[]" }

      it "raises a Dependabot::DependencyFileNotFound error" do
        expect { file_fetcher_instance.files }.
          to raise_error(Dependabot::DependencyFileNotFound) do |error|
            expect(error.file_name).to eq("requirements.txt")
          end
      end
    end

    context "with a requirements.txt and a setup.py" do
      let(:repo_contents) do
        fixture("github", "contents_python.json")
      end

      before do
        stub_request(:get, url + "requirements.txt?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "requirements_content.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "setup.py?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "setup_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the requirements.txt and the setup.py file" do
        expect(file_fetcher_instance.files.count).to eq(2)
        expect(file_fetcher_instance.files.map(&:name)).
          to include("setup.py")
      end
    end

    context "with a requirements.txt and a pip.conf" do
      let(:repo_contents) do
        fixture("github", "contents_python_with_conf.json")
      end

      before do
        stub_request(:get, url + "requirements.txt?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "requirements_content.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "pip.conf?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "setup_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the requirements.txt and the pip.conf file" do
        expect(file_fetcher_instance.files.count).to eq(2)
        expect(file_fetcher_instance.files.map(&:name)).
          to include("pip.conf")
      end
    end

    context "with a requirements.txt, a setup.py and a requirements folder" do
      let(:repo_contents) do
        fixture("github", "contents_python_repo.json")
      end

      before do
        stub_request(:get, url + "requirements.txt?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "requirements_content.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "setup.py?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "setup_content.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "requirements?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "contents_python_requirements_folder.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "requirements/coverage.txt?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "requirements_content.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "requirements/test.txt?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "requirements_content.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "requirements/tools.txt?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "requirements_content.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "requirements/typing.txt?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "requirements_content.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "requirements/coverage.in?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "requirements_content.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "requirements/test.in?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "requirements_content.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "requirements/tools.in?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "requirements_content.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "requirements/typing.in?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "requirements_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the right files file" do
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(
            %w(
              requirements.txt
              setup.py
              requirements/coverage.txt
              requirements/test.txt
              requirements/tools.txt
              requirements/typing.txt
              requirements/coverage.in
              requirements/test.in
              requirements/tools.in
              requirements/typing.in
            )
          )
      end
    end

    context "with a cascading requirement" do
      let(:repo_contents) do
        fixture("github", "contents_python_only_requirements.json")
      end

      before do
        stub_request(:get, url + "requirements.txt?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "requirements_with_cascade.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      context "that is fetchable" do
        before do
          stub_request(:get, url + "more_requirements.txt?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "requirements_content.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "no_dot/more_requirements.txt?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "requirements_content.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "comment_more_requirements.txt?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "requirements_content.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches the additional requirements" do
          expect(file_fetcher_instance.files.count).to eq(4)
          expect(file_fetcher_instance.files.map(&:name)).
            to include("more_requirements.txt").
            and include("no_dot/more_requirements.txt").
            and include("comment_more_requirements.txt")
        end

        context "and is circular" do
          before do
            stub_request(:get, url + "requirements.txt?ref=sha").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: fixture("github", "requirements_with_circular.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          it "only fetches the additional requirements once" do
            expect(file_fetcher_instance.files.count).to eq(1)
          end
        end

        context "and cascades more than once" do
          before do
            stub_request(:get, url + "no_dot/more_requirements.txt?ref=sha").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: fixture(
                  "github", "requirements_with_simple_cascade.json"
                ),
                headers: { "content-type" => "application/json" }
              )
            stub_request(
              :get, url + "no_dot/cascaded_requirements.txt?ref=sha"
            ).with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: fixture("github", "requirements_content.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          it "fetches the additional requirements" do
            expect(file_fetcher_instance.files.count).to eq(5)
            expect(file_fetcher_instance.files.map(&:name)).
              to include("no_dot/more_requirements.txt").
              and include("no_dot/cascaded_requirements.txt")
          end
        end
      end

      context "that has an unfetchable path" do
        before do
          stub_request(:get, url + "more_requirements.txt?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(status: 404)
        end

        it "raises a DependencyFileNotFound error with details" do
          expect { file_fetcher_instance.files }.
            to raise_error(Dependabot::DependencyFileNotFound)
        end
      end
    end

    context "with a constraints file" do
      let(:repo_contents) do
        fixture("github", "contents_python_only_requirements.json")
      end

      before do
        stub_request(:get, url + "requirements.txt?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "requirements_with_constraint.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      context "that is fetchable" do
        before do
          stub_request(:get, url + "constraints.txt?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "python_constraints_content.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches the constraints file" do
          expect(file_fetcher_instance.files.count).to eq(2)
          expect(file_fetcher_instance.files.map(&:name)).
            to include("constraints.txt")
        end
      end

      context "that has an unfetchable path" do
        before do
          stub_request(:get, url + "constraints.txt?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(status: 404)
        end

        it "raises a DependencyFileNotFound error with details" do
          expect { file_fetcher_instance.files }.
            to raise_error(Dependabot::DependencyFileNotFound)
        end
      end
    end

    context "with a path-based dependency" do
      let(:repo_contents) do
        fixture("github", "contents_python_only_requirements.json")
      end

      before do
        stub_request(:get, url + "requirements.txt?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "requirements_with_self_reference.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      context "that is fetchable" do
        before do
          stub_request(:get, url + "setup.py?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "setup_content.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches the setup.py" do
          expect(file_fetcher_instance.files.count).to eq(2)
          expect(file_fetcher_instance.files.map(&:name)).
            to include("setup.py")
        end

        context "and references extras" do
          let(:requirements_txt) do
            fixture("github", "requirements_with_self_reference_extras.json")
          end

          before do
            stub_request(:get, url + "requirements.txt?ref=sha").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: requirements_txt,
                headers: { "content-type" => "application/json" }
              )
          end

          it "fetches the setup.py" do
            expect(file_fetcher_instance.files.count).to eq(2)
            expect(file_fetcher_instance.files.map(&:name)).
              to include("setup.py")
          end
        end

        context "but is in a child requirement file" do
          before do
            stub_request(:get, url + "requirements.txt?ref=sha").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: fixture("github", "requirements_with_cascade.json"),
                headers: { "content-type" => "application/json" }
              )
            stub_request(:get, url + "more_requirements.txt?ref=sha").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: fixture(
                  "github", "requirements_with_self_reference.json"
                ),
                headers: { "content-type" => "application/json" }
              )
            stub_request(:get, url + "no_dot/more_requirements.txt?ref=sha").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: fixture("github", "requirements_content.json"),
                headers: { "content-type" => "application/json" }
              )
            stub_request(:get, url + "comment_more_requirements.txt?ref=sha").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: fixture("github", "requirements_content.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          it "fetches the setup.py" do
            expect(file_fetcher_instance.files.count).to eq(5)
            expect(file_fetcher_instance.files.map(&:name)).
              to include("setup.py")
          end
        end
      end

      context "that has an unfetchable path" do
        before do
          stub_request(:get, url + "setup.py?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(status: 404)
        end

        it "raises a PathDependenciesNotReachable error with details" do
          expect { file_fetcher_instance.files }.
            to raise_error(
              Dependabot::PathDependenciesNotReachable,
              "The following path based dependencies could not be retrieved: " \
              "setup.py"
            )
        end
      end
    end
  end
end
