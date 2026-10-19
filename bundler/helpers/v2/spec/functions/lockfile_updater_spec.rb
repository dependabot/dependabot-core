# typed: false
# frozen_string_literal: true

require "native_spec_helper"
require "rubygems/indexer"
require "tmpdir"

RSpec.describe Functions::LockfileUpdater do
  around do |example|
    original_gemfile = ENV.fetch("BUNDLE_GEMFILE", nil)
    Dir.mktmpdir("lockfile_updater_spec_") do |dir|
      Dir.chdir(dir) do
        ENV["BUNDLE_GEMFILE"] = File.join(dir, "Gemfile")
        Bundler.reset!
        Bundler.ui = Bundler::UI::Silent.new
        example.run
      end
    end
  ensure
    ENV["BUNDLE_GEMFILE"] = original_gemfile
    Bundler.reset!
  end

  before do
    repository = File.expand_path("repository")
    FileUtils.mkdir_p(File.join(repository, "gems"))
    gems = [
      ["app", "1.0.0", { "mail" => ">= 2.8.1", "net-protocol" => ">= 0" }],
      ["mail", "2.8.1", { "mini_mime" => ">= 0.1.1", "net-protocol" => ">= 0" }],
      ["mail", "2.9.1", { "mini_mime" => ">= 0.1.1", "net-protocol" => ">= 0" }],
      ["mail", "3.0.0", { "mini_mime" => ">= 2.0", "net-protocol" => ">= 0.4" }],
      ["mini_mime", "1.1.5", {}], ["mini_mime", "1.1.6", {}], ["mini_mime", "2.0.0", {}],
      ["net-protocol", "0.2.2", { "timeout" => ">= 0" }],
      ["net-protocol", "0.4.0", { "timeout" => ">= 0" }],
      ["timeout", "0.4.3", {}], ["timeout", "0.6.1", {}]
    ]
    Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) do
      Dir.chdir(File.join(repository, "gems")) do
        gems.each do |name, version, dependencies|
          spec = Gem::Specification.new do |gem_spec|
            gem_spec.name = name
            gem_spec.version = version
            gem_spec.summary = "Offline resolver regression fixture"
            gem_spec.authors = ["Test"]
            dependencies.each { |dependency, requirement| gem_spec.add_runtime_dependency(dependency, requirement) }
          end
          Gem::Package.build(spec, true)
        end
      end
      Gem::Indexer.new(repository).generate_index
    end
    File.write("Gemfile", "source 'file://#{repository}'\ngem 'app'\n")
    File.write("Gemfile.lock", <<~LOCKFILE)
      GEM
        remote: file://#{repository}/
        specs:
          app (1.0.0)
            mail (>= 2.8.1)
            net-protocol
          mail (2.8.1)
            mini_mime (>= 0.1.1)
            net-protocol
          mini_mime (1.1.5)
          net-protocol (0.2.2)
            timeout
          timeout (0.4.3)

      PLATFORMS
        ruby

      DEPENDENCIES
        app
    LOCKFILE
  end

  let(:updated_lockfile) do
    updater = described_class.new(
      gemfile_name: "Gemfile",
      lockfile_name: "Gemfile.lock",
      dependencies: [{ "name" => "mail", "version" => target_version, "requirements" => [] }]
    )
    Bundler::LockfileParser.new(updater.run)
  end
  let(:versions) { updated_lockfile.specs.to_h { |spec| [spec.name, spec.version.to_s] } }
  let(:target_version) { "2.9.1" }

  it "updates an indirect dependency while keeping compatible locked dependencies" do
    expect(versions).to eq(
      "app" => "1.0.0", "mail" => "2.9.1", "mini_mime" => "1.1.5",
      "net-protocol" => "0.2.2", "timeout" => "0.4.3"
    )
    expect(updated_lockfile.dependencies.keys).to eq(["app"])
  end

  context "when the requested update requires newer dependencies" do
    let(:target_version) { "3.0.0" }

    it "allows major and minor upgrades while keeping compatible locked descendants" do
      expect(versions).to eq(
        "app" => "1.0.0", "mail" => "3.0.0", "mini_mime" => "2.0.0",
        "net-protocol" => "0.4.0", "timeout" => "0.4.3"
      )
    end
  end
end
