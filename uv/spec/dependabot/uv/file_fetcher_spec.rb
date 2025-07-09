# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/uv/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Uv::FileFetcher do
  it_behaves_like "a dependency file fetcher"

  describe ".required_files_in?" do
    subject { described_class.required_files_in?(filenames) }

    context "with only a requirements.in" do
      let(:filenames) { %w(requirements.in) }

      it { is_expected.to be(true) }
    end

    context "with only a requirements.txt" do
      let(:filenames) { %w(requirements.txt) }

      it { is_expected.to be(true) }
    end

    context "with only a requirements folder" do
      let(:filenames) { %w(requirements) }

      it { is_expected.to be(true) }
    end

    context "with only a requirements-dev" do
      let(:filenames) { %w(requirements-dev.txt) }

      it { is_expected.to be(true) }
    end

    context "with a pyproject.toml" do
      let(:filenames) { %w(pyproject.toml) }

      it { is_expected.to be(true) }
    end

    context "with no requirements" do
      let(:filenames) { %w(requirements-dev.md) }

      it { is_expected.to be(false) }
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
    let(:url_with_directory) { File.join(url, directory) }
    let(:credentials) do
      [Dependabot::Credential.new({
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      })]
    end

    let(:json_header) { { "content-type" => "application/json" } }
    let(:repo_contents) do
      fixture("github", "contents_python_only_requirements.json")
    end

    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")

      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 200, body: repo_contents, headers: json_header)

      %w(app build_scripts data migrations tests).each do |dir|
        stub_request(:get, File.join(url_with_directory, "#{dir}?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 200, body: "[]", headers: json_header)
      end

      stub_request(:get, File.join(url_with_directory, "todo.txt?ref=sha"))
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_todo_txt.json"),
          headers: json_header
        )
    end

    context "with only a requirements.in" do
      let(:repo_contents) do
        fixture("github", "contents_python_only_requirements_in.json")
      end

      before do
        stub_request(:get, url + "requirements.in?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "requirements_in_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the requirements.in file" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name))
          .to eq(["requirements.in"])
      end
    end

    context "with only a requirements.txt" do
      let(:repo_contents) do
        fixture("github", "contents_python_only_requirements.json")
      end
      let(:requirements_fixture_name) { "requirements_content.json" }

      before do
        stub_request(:get, url + "requirements.txt?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", requirements_fixture_name),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the requirements.txt file" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name))
          .to eq(["requirements.txt"])
      end

      context "when including comments" do
        let(:requirements_fixture_name) { "requirements_with_comments.json" }

        it "fetches the requirements.txt file" do
          expect(file_fetcher_instance.files.count).to eq(1)
          expect(file_fetcher_instance.files.map(&:name))
            .to eq(["requirements.txt"])
        end
      end

      context "when including --no-binary" do
        let(:requirements_fixture_name) { "requirements_with_no_binary.json" }

        it "fetches the requirements.txt file" do
          expect(file_fetcher_instance.files.count).to eq(1)
          expect(file_fetcher_instance.files.map(&:name))
            .to eq(["requirements.txt"])
        end
      end

      context "when dealing with a todo.txt that is actually a requirements file" do
        before do
          stub_request(:get, url + "todo.txt?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", todo_fixture_name),
              headers: { "content-type" => "application/json" }
            )
        end

        let(:todo_fixture_name) { "requirements_content.json" }

        it "fetches the unexpectedly named file" do
          expect(file_fetcher_instance.files.count).to eq(2)
          expect(file_fetcher_instance.files.map(&:name))
            .to match_array(%w(todo.txt requirements.txt))
        end

        context "when including comments" do
          let(:todo_fixture_name) { "requirements_with_comments.json" }

          it "fetches the unexpectedly named file" do
            expect(file_fetcher_instance.files.count).to eq(2)
            expect(file_fetcher_instance.files.map(&:name))
              .to match_array(%w(todo.txt requirements.txt))
          end
        end
      end

      context "when dealing with a todo.txt can't be encoded to UTF-8" do
        before do
          stub_request(:get, url + "todo.txt?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "contents_image.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches the requirements.txt file" do
          expect(file_fetcher_instance.files.count).to eq(1)
          expect(file_fetcher_instance.files.map(&:name))
            .to eq(["requirements.txt"])
        end
      end
    end

    context "with only a pyproject.toml" do
      let(:repo_contents) do
        fixture("github", "contents_python_only_pyproject.json")
      end

      before do
        stub_request(:get, url + "pyproject.toml?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_python_pyproject.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the pyproject.toml" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name))
          .to match_array(%w(pyproject.toml))
      end
    end

    context "with only a uv.lock" do
      let(:repo_contents) do
        fixture("github", "contents_python_only_uv_lock.json")
      end

      before do
        stub_request(:get, url + "uv.lock?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_python_uv_lock.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "raises a Dependabot::DependencyFileNotFound error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "with a uv.lock file and a pyproject.toml" do
      let(:repo_contents) do
        fixture("github", "contents_python_uv_lock_and_pyproject.json")
      end

      before do
        stub_request(:get, url + "uv.lock?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_python_uv_lock.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "pyproject.toml?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_python_pyproject.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the pyproject.toml" do
        expect(file_fetcher_instance.files.count).to eq(2)
        expect(file_fetcher_instance.files.map(&:name))
          .to match_array(%w(pyproject.toml uv.lock))
      end
    end

    context "with requirements.txt, requirements.in, or pyproject.toml" do
      let(:repo_contents) { "[]" }

      it "raises a Dependabot::DependencyFileNotFound error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "with a cascading requirement" do
      let(:repo_contents) do
        fixture("github", "contents_python_only_requirements.json")
      end

      before do
        stub_request(:get, url + "requirements.txt?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "requirements_with_cascade.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      context "when fetchable" do
        before do
          stub_request(:get, url + "more_requirements.txt?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "requirements_content.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "no_dot/more_requirements.txt?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "requirements_content.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "comment_more_requirements.txt?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "requirements_content.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches the additional requirements" do
          expect(file_fetcher_instance.files.count).to eq(4)
          expect(file_fetcher_instance.files.map(&:name))
            .to include("more_requirements.txt")
            .and include("no_dot/more_requirements.txt")
            .and include("comment_more_requirements.txt")
        end

        context "when dealing with circular" do
          before do
            stub_request(:get, url + "requirements.txt?ref=sha")
              .with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: fixture("github", "requirements_with_circular.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          it "only fetches the additional requirements once" do
            expect(file_fetcher_instance.files.count).to eq(1)
          end
        end

        context "when dealing with a .in file" do
          before do
            stub_request(:get, url + "requirements.txt?ref=sha")
              .with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: fixture("github", "requirements_with_in_child.json"),
                headers: { "content-type" => "application/json" }
              )
            stub_request(:get, url + "some/nested/req.in?ref=sha")
              .with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: fixture("github", "requirements_content.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          it "fetches the .in file" do
            expect(file_fetcher_instance.files.count).to eq(2)
            expect(file_fetcher_instance.files.map(&:name))
              .to include("some/nested/req.in")
          end
        end

        context "when cascading more than once" do
          before do
            stub_request(:get, url + "no_dot/more_requirements.txt?ref=sha")
              .with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: fixture(
                  "github", "requirements_with_simple_cascade.json"
                ),
                headers: { "content-type" => "application/json" }
              )
            stub_request(
              :get, url + "no_dot/cascaded_requirements.txt?ref=sha"
            ).with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: fixture("github", "requirements_content.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          it "fetches the additional requirements" do
            expect(file_fetcher_instance.files.count).to eq(5)
            expect(file_fetcher_instance.files.map(&:name))
              .to include("no_dot/more_requirements.txt")
              .and include("no_dot/cascaded_requirements.txt")
          end
        end
      end

      context "when an unfetchable path is present" do
        before do
          stub_request(:get, url + "more_requirements.txt?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(status: 404)
        end

        it "raises a DependencyFileNotFound error with details" do
          expect { file_fetcher_instance.files }
            .to raise_error(Dependabot::DependencyFileNotFound)
        end
      end
    end

    context "with a constraints file" do
      let(:repo_contents) do
        fixture("github", "contents_python_only_requirements.json")
      end

      before do
        stub_request(:get, url + "requirements.txt?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "requirements_with_constraint.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      context "when fetchable" do
        before do
          stub_request(:get, url + "constraints.txt?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "python_constraints_content.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches the constraints file" do
          expect(file_fetcher_instance.files.count).to eq(2)
          expect(file_fetcher_instance.files.map(&:name))
            .to include("constraints.txt")
        end
      end

      context "when an unfetchable path is present" do
        before do
          stub_request(:get, url + "constraints.txt?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(status: 404)
        end

        it "raises a DependencyFileNotFound error with details" do
          expect { file_fetcher_instance.files }
            .to raise_error(Dependabot::DependencyFileNotFound)
        end
      end
    end

    context "with a path-based dependency that it's not fetchable" do
      let(:directory) { "/requirements" }

      let(:repo_contents) do
        fixture("github", "contents_directory_with_outside_reference_root.json")
      end

      before do
        stub_request(:get, url_with_directory + "?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_directory_with_outside_reference.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, File.join(url_with_directory, "base.in?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_directory_with_outside_reference_in_file.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, File.join(url_with_directory, "base.txt?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_directory_with_outside_reference_txt_file.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, File.join(url_with_directory, "setup.py?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 404)
        stub_request(:get, File.join(url_with_directory, "pyproject.toml?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 404)
      end

      it "raises DependencyFileNotFound error with details" do
        expect { file_fetcher_instance.files }
          .to raise_error(
            Dependabot::PathDependenciesNotReachable,
            "The following path based dependencies could not be retrieved: \"-e file:.\" at /requirements/base.in"
          )
      end
    end

    context "with a path-based dependency that is fetchable" do
      let(:repo_contents) do
        fixture("github", "contents_python_only_requirements.json")
      end

      before do
        stub_request(:get, url + "requirements.txt?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "requirements_with_self_reference.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "setup.py?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "setup_content.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "setup.cfg?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 404,
            body: fixture("github", "setup_content.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "pyproject.toml?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_python_pyproject.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the setup.py" do
        expect(file_fetcher_instance.files.count).to eq(2)
        expect(file_fetcher_instance.files.map(&:name)).to include("requirements.txt")
        expect(file_fetcher_instance.files.map(&:name)).to include("pyproject.toml")
      end

      context "when using a variety of quote styles" do
        before do
          stub_request(:get, url + "requirements.txt?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body:
                fixture("github", "requirements_with_path_dependencies.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "my/setup.py?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "setup_content.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "my/setup.cfg?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(status: 404)
          stub_request(:get, url + "my?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: "[]",
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "my-single/setup.py?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "setup_content.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "my-single/setup.cfg?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(status: 404)
          stub_request(:get, url + "my-single?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: "[]",
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "my-other/setup.py?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "setup_content.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "my-other/setup.cfg?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "setup_content.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "some/zip-file.tar.gz?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "setup_content.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "file:./setup.py?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(status: 404)
          stub_request(:get, url + "my/pyproject.toml?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "contents_python_pyproject.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "my-single/pyproject.toml?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "contents_python_pyproject.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "my-other/pyproject.toml?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "contents_python_pyproject.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches the path dependencies" do
          expect(file_fetcher_instance.files.map(&:name))
            .to match_array(
              %w(requirements.txt pyproject.toml my/pyproject.toml my-single/pyproject.toml
                 my-other/pyproject.toml some/zip-file.tar.gz)
            )
        end
      end

      context "when in a child requirement file" do
        before do
          stub_request(:get, url + "requirements.txt?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "requirements_with_cascade.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "more_requirements.txt?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "requirements_content.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "no_dot/more_requirements.txt?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture(
                "github", "requirements_with_self_reference.json"
              ),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "comment_more_requirements.txt?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "requirements_content.json"),
              headers: { "content-type" => "application/json" }
            )

          stub_request(:get, url + "no_dot?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(status: 200, body: repo_contents, headers: json_header)
          stub_request(:get, url + "no_dot/setup.py?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "setup_content.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches the pyproject.toml (does not look in the nested directory)" do
          expect(file_fetcher_instance.files.count).to eq(5)
          expect(file_fetcher_instance.files.map(&:name))
            .to include("pyproject.toml")
        end
      end
    end

    context "with a pyproject.toml and a requirements.txt file that does not use setup.py" do
      let(:repo_contents) do
        fixture("github", "contents_python_pyproject_and_requirements_without_setup_py.json")
      end

      before do
        stub_request(:get, url + "requirements-test.txt?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "requirements_with_self_reference.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "pyproject.toml?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_python_pyproject.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "setup.cfg?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "setup_cfg_content.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "setup.py?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 404)
      end

      it "doesn't raise a path dependency error" do
        expect(file_fetcher_instance.files.count).to eq(2)
        expect(file_fetcher_instance.files.map(&:name)).to contain_exactly("requirements-test.txt", "pyproject.toml")
      end
    end

    context "with a git dependency" do
      let(:repo_contents) do
        fixture("github", "contents_python_only_requirements.json")
      end
      let(:requirements_contents) do
        fixture("github", "requirements_with_git_reference.json")
      end

      before do
        stub_request(:get, url + "requirements.txt?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: requirements_contents,
            headers: { "content-type" => "application/json" }
          )
      end

      it "doesn't confuse the git reference for a path reference" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.first.name).to eq("requirements.txt")
      end

      context "when using a git URL" do
        let(:requirements_contents) do
          fixture("github", "requirements_with_git_url_reference.json")
        end

        it "doesn't confuse the git reference for a path reference" do
          expect(file_fetcher_instance.files.count).to eq(1)
          expect(file_fetcher_instance.files.first.name)
            .to eq("requirements.txt")
        end
      end
    end

    context "with a very large requirements.txt file" do
      let(:repo_contents) do
        fixture("github", "contents_python_large_requirements_txt.json")
      end

      it "raises a Dependabot::DependencyFileNotFound error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "with UV sources path dependencies" do
      describe "#uv_sources_path_dependencies" do
        let(:pyproject_content) { fixture("pyproject_files", "uv_path_dependencies.toml") }
        let(:pyproject_file) do
          Dependabot::DependencyFile.new(
            name: "pyproject.toml",
            content: pyproject_content
          )
        end

        before do
          allow(file_fetcher_instance).to receive(:pyproject).and_return(pyproject_file)
        end

        it "detects UV sources path dependencies" do
          path_deps = file_fetcher_instance.send(:uv_sources_path_dependencies)
          expect(path_deps).to contain_exactly(
            { name: "protos", path: "../protos", file: "pyproject.toml" },
            { name: "another-local", path: "local-lib", file: "pyproject.toml" }
          )
        end

        it "includes UV sources in path_dependencies method" do
          # Mock other path dependency methods to return empty arrays for isolation
          allow(file_fetcher_instance).to receive(:requirement_txt_path_dependencies).and_return([])
          allow(file_fetcher_instance).to receive(:requirement_in_path_dependencies).and_return([])

          all_path_deps = file_fetcher_instance.send(:path_dependencies)
          expect(all_path_deps).to contain_exactly(
            { name: "protos", path: "../protos", file: "pyproject.toml" },
            { name: "another-local", path: "./local-lib", file: "pyproject.toml" }
          )
        end

        context "when pyproject.toml has no UV sources" do
          let(:pyproject_content) { fixture("pyproject_files", "uv_simple.toml") }

          it "returns empty array for UV sources path dependencies" do
            path_deps = file_fetcher_instance.send(:uv_sources_path_dependencies)
            expect(path_deps).to be_empty
          end
        end

        context "when UV sources contain non-path dependencies" do
          let(:pyproject_content) { fixture("pyproject_files", "uv_mixed_sources.toml") }

          it "only detects path-based UV sources" do
            path_deps = file_fetcher_instance.send(:uv_sources_path_dependencies)
            expect(path_deps).to contain_exactly(
              { name: "local-package", path: "./local-package", file: "pyproject.toml" }
            )
          end
        end

        context "when pyproject.toml is nil" do
          before do
            allow(file_fetcher_instance).to receive(:pyproject).and_return(nil)
          end

          it "returns empty array" do
            path_deps = file_fetcher_instance.send(:uv_sources_path_dependencies)
            expect(path_deps).to be_empty
          end
        end
      end
    end
  end
end
