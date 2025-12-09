# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_group"
require "dependabot/job"
require "dependabot/updater/group_dependency_selector"

RSpec.describe Dependabot::Updater::GroupDependencySelector do
  let(:group_name) { "backend-dependencies" }
  let(:dependency_group) do
    instance_double(
      Dependabot::DependencyGroup,
      name: group_name,
      dependencies: [],
      rules: group_rules
    )
  end

  let(:group_rules) do
    {
      "patterns" => ["rails", "pg", "redis*"]
    }
  end

  let(:dependency_snapshot) do
    instance_double(
      Dependabot::DependencySnapshot,
      ecosystem: "bundler",
      groups: []
    )
  end

  let(:selector) { described_class.new(group: dependency_group, dependency_snapshot: dependency_snapshot) }

  let(:job) do
    instance_double(
      Dependabot::Job,
      source: instance_double(Dependabot::Source, directory: "/api")
    )
  end

  before do
    allow(Dependabot).to receive(:logger).and_return(
      instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil)
    )
  end

  describe "#initialize" do
    it "stores group and dependency snapshot" do
      expect(selector).to respond_to(:merge_per_directory!)
      expect(selector).to respond_to(:filter_to_group!)
      expect(selector).to respond_to(:annotate_dependency_drift!)
    end
  end

  describe "#merge_per_directory!" do
    let(:rails_dep) { create_dependency("rails", "7.0.0") }
    let(:pg_dep) { create_dependency("pg", "1.4.0") }
    let(:redis_dep) { create_dependency("redis", "4.8.0") }
    let(:duplicate_rails_dep) { create_dependency("rails", "7.0.1") }

    let(:change1) do
      create_dependency_change(
        job: job,
        dependencies: [rails_dep, pg_dep],
        files: [create_dependency_file("Gemfile", "/api")]
      )
    end

    let(:change2) do
      create_dependency_change(
        job: create_job("/web"),
        dependencies: [redis_dep, duplicate_rails_dep],
        files: [create_dependency_file("Gemfile", "/web")]
      )
    end

    context "with single change" do
      it "returns the original change" do
        result = selector.merge_per_directory!([change1])
        expect(result).to eq(change1)
      end
    end

    context "with multiple changes" do
      before do
        allow(Dependabot::DependencyChange).to receive(:new) do |args|
          instance_double(
            Dependabot::DependencyChange,
            job: args[:job],
            updated_dependencies: args[:updated_dependencies],
            updated_dependency_files: args[:updated_dependency_files]
          )
        end
      end

      it "merges dependencies with directory-aware deduplication" do
        result = selector.merge_per_directory!([change1, change2])

        expect(result.updated_dependencies.length).to eq(4)
        dependency_names = result.updated_dependencies.map(&:name)
        expect(dependency_names).to contain_exactly("rails", "pg", "redis", "rails")
      end

      it "merges updated files without duplicates" do
        result = selector.merge_per_directory!([change1, change2])

        expect(result.updated_dependency_files.length).to eq(2)
        file_paths = result.updated_dependency_files.map { |f| [f.directory, f.name] }
        expect(file_paths).to contain_exactly(["/api", "Gemfile"], ["/web", "Gemfile"])
      end

      it "logs merge statistics" do
        expect(Dependabot.logger).to receive(:info).with(
          "GroupDependencySelector merged 2 directory changes into 4 unique dependencies " \
          "[group=#{group_name}, ecosystem=bundler]"
        )

        selector.merge_per_directory!([change1, change2])
      end
    end
  end

  describe "#filter_to_group!" do
    let(:rails_dep) { create_dependency("rails", "7.0.0") }
    let(:unauthorized_dep) { create_dependency("puma", "5.6.0") }
    let(:redis_dep) { create_dependency("redis-client", "0.11.0") }

    let(:dependency_change) do
      create_dependency_change(
        job: job,
        dependencies: [rails_dep, unauthorized_dep, redis_dep],
        files: [create_dependency_file("Gemfile.lock", "/api")]
      )
    end

    context "when feature flag is disabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_membership_enforcement).and_return(false)
      end

      it "does not modify the dependency change" do
        original_deps = dependency_change.updated_dependencies.dup
        selector.filter_to_group!(dependency_change)
        expect(dependency_change.updated_dependencies).to eq(original_deps)
      end
    end

    context "when feature flag is enabled" do
      before do
        allow(Dependabot::Utils).to receive(:version_class_for_package_manager).and_return(Dependabot::Version)

        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_membership_enforcement).and_return(true)

        allow(dependency_group).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
        allow(dependency_group).to receive(:respond_to?).with(:applies_to).and_return(false)
        allow(dependency_group).to receive(:contains?) do |dep|
          %w(rails redis-client).include?(dep.name)
        end

        allow(job).to receive_messages(ignore_conditions_for: [], allowed_update?: true)

        allow(dependency_change.updated_dependencies).to receive(:clear)
        allow(dependency_change.updated_dependencies).to receive(:concat)
      end

      it "filters out non-group dependencies" do
        original_deps = dependency_change.updated_dependencies.dup
        selector.filter_to_group!(dependency_change)

        expected_deps = %w(rails redis-client)
        included_deps = original_deps.select { |dep| expected_deps.include?(dep.name) }
        expect(included_deps.length).to eq(2)
      end

      it "preserves file diffs" do
        original_files = dependency_change.updated_dependency_files
        selector.filter_to_group!(dependency_change)
        expect(dependency_change.updated_dependency_files).to eq(original_files)
      end

      it "emits filtering metrics when dependencies are filtered" do
        expect(selector).to receive(:emit_filtering_metrics)
          .with("/api", 3, anything, anything)

        selector.filter_to_group!(dependency_change)
      end

      it "logs filtered dependencies" do
        expect(selector).to receive(:log_filtered_dependencies) do |filtered_deps|
          expect(filtered_deps.any?).to be true
        end

        selector.filter_to_group!(dependency_change)
      end
    end

    context "with fallback group membership logic" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_membership_enforcement).and_return(true)

        allow(dependency_group).to receive(:respond_to?)
          .with(:contains_dependency?).and_return(false)
        allow(dependency_group).to receive(:respond_to?)
          .with(:applies_to).and_return(false)

        allow(dependency_group).to receive(:contains?) do |dep|
          %w(rails redis-client).include?(dep.name)
        end

        allow(job).to receive_messages(ignore_conditions_for: [], allowed_update?: true)

        allow(dependency_change.updated_dependencies).to receive(:clear)
        allow(dependency_change.updated_dependencies).to receive(:concat)
      end

      it "uses pattern matching fallback" do
        expect(dependency_group).to receive(:contains?).at_least(:once).and_return(true)

        selector.filter_to_group!(dependency_change)
      end
    end
  end

  describe "#annotate_dependency_drift!" do
    let(:dependency_change) do
      create_dependency_change(
        job: job,
        dependencies: [create_dependency("rails", "7.0.0")],
        files: [create_dependency_file("Gemfile.lock", "/api")]
      )
    end

    context "when feature flag is disabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_membership_enforcement).and_return(false)
      end

      it "does not annotate dependency drift" do
        expect(selector).not_to receive(:detect_file_dependency_drift)
        selector.annotate_dependency_drift!(dependency_change)
      end
    end

    context "when feature flag is enabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_membership_enforcement).and_return(true)
      end

      it "processes files for dependency drift" do
        allow(selector).to receive(:detect_file_dependency_drift)
          .and_return(%w(transitive-dep-1 transitive-dep-2))

        selector.annotate_dependency_drift!(dependency_change)

        expect(selector).to have_received(:detect_file_dependency_drift)
      end

      it "emits dependency drift metrics when drift is detected" do
        allow(selector).to receive(:detect_file_dependency_drift).and_return(["transitive-dep"])
        expect(selector).to receive(:emit_dependency_drift_metrics).with("/api", 1)

        selector.annotate_dependency_drift!(dependency_change)
      end

      it "logs dependency drift" do
        allow(selector).to receive(:detect_file_dependency_drift).and_return(["transitive-dep"])
        expect(selector).to receive(:log_dependency_drift).with(["transitive-dep"])

        selector.annotate_dependency_drift!(dependency_change)
      end
    end
  end

  describe "pattern specificity functionality" do
    let(:docker_dep) { create_dependency("docker-compose", "2.0.0") }
    let(:nginx_dep) { create_dependency("nginx", "1.21.0") }
    let(:redis_dep) { create_dependency("redis-client", "0.11.0") }

    let(:generic_group) do
      instance_double(
        Dependabot::DependencyGroup,
        name: "all-dependencies",
        dependencies: [],
        rules: { "patterns" => ["*"] }
      )
    end

    let(:docker_group) do
      instance_double(
        Dependabot::DependencyGroup,
        name: "docker-dependencies",
        dependencies: [],
        rules: { "patterns" => ["docker*"] }
      )
    end

    let(:exact_group) do
      instance_double(
        Dependabot::DependencyGroup,
        name: "exact-nginx",
        dependencies: [],
        rules: { "patterns" => ["nginx"] }
      )
    end

    let(:snapshot_with_multiple_groups) do
      instance_double(
        Dependabot::DependencySnapshot,
        ecosystem: "bundler",
        groups: [generic_group, docker_group, exact_group]
      )
    end

    describe "#dependency_belongs_to_more_specific_group?" do
      let(:specificity_calculator) do
        instance_double(
          Dependabot::Updater::PatternSpecificityCalculator,
          dependency_belongs_to_more_specific_group?: false
        )
      end

      let(:generic_selector) do
        described_class.new(group: generic_group, dependency_snapshot: snapshot_with_multiple_groups)
      end

      before do
        [generic_group, docker_group, exact_group].each do |g|
          allow(g).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
          allow(g).to receive(:respond_to?).with(:applies_to).and_return(false)
        end

        allow(generic_group).to receive_messages(contains?: true, dependencies: [])
        allow(docker_group).to receive(:contains?) { |dep| dep.name.start_with?("docker") }
        allow(exact_group).to receive(:contains?) { |dep| dep.name == "nginx" }
      end

      it "returns true when dependency belongs to more specific docker group" do
        result = generic_selector.send(:dependency_belongs_to_more_specific_group?, docker_dep, "/api")
        expect(result).to be true
      end

      it "returns true when dependency belongs to exact match group" do
        result = generic_selector.send(:dependency_belongs_to_more_specific_group?, nginx_dep, "/api")
        expect(result).to be true
      end

      it "returns false when no more specific group exists" do
        docker_selector = described_class.new(group: docker_group, dependency_snapshot: snapshot_with_multiple_groups)
        result = docker_selector.send(:dependency_belongs_to_more_specific_group?, docker_dep, "/api")
        expect(result).to be false
      end
    end

    describe "update-type aware specificity" do
      let(:specificity_calculator) do
        instance_double(
          Dependabot::Updater::PatternSpecificityCalculator,
          dependency_belongs_to_more_specific_group?: false
        )
      end
      let(:generic_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "all-dependencies",
          dependencies: [],
          rules: { "patterns" => ["*"] }
        )
      end

      let(:docker_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "docker-dependencies",
          dependencies: [],
          rules: { "patterns" => ["docker*"], "update-types" => ["patch"] }
        )
      end

      let(:snapshot_with_multiple_groups) do
        instance_double(
          Dependabot::DependencySnapshot,
          ecosystem: "bundler",
          groups: [generic_group, docker_group]
        )
      end

      let(:generic_selector) do
        described_class.new(group: generic_group, dependency_snapshot: snapshot_with_multiple_groups)
      end

      let(:docker_dep_minor_update) do
        Dependabot::Dependency.new(
          name: "docker-compose",
          package_manager: "bundler",
          version: "2.1.0",
          previous_version: "2.0.0",
          requirements: [
            {
              file: "Gemfile",
              requirement: "~> 2.1.0",
              groups: ["default"],
              source: nil
            }
          ],
          previous_requirements: [
            {
              file: "Gemfile",
              requirement: "~> 2.0.0",
              groups: ["default"],
              source: nil
            }
          ],
          directory: "/api",
          subdependency_metadata: [],
          removed: false,
          metadata: {}
        )
      end

      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_membership_enforcement).and_return(true)

        [generic_group, docker_group].each do |g|
          allow(g).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
          allow(g).to receive(:respond_to?).with(:applies_to).and_return(false)
        end

        allow(Dependabot::Updater::PatternSpecificityCalculator).to receive(:new).and_return(specificity_calculator)
        allow(generic_selector).to receive(:update_type_for_dependency).and_return("minor")

        allow(generic_group).to receive_messages(contains?: true, dependencies: [])
        allow(docker_group).to receive(:contains?) { |dep| dep.name.start_with?("docker") }
      end

      it "does not filter dependency when more specific group disallows its update type" do
        expect(generic_selector.send(:update_type_for_dependency, docker_dep_minor_update)).to eq("minor")
        result = generic_selector.send(:dependency_belongs_to_more_specific_group?, docker_dep_minor_update, "/api")
        expect(result).to be false

        expect(specificity_calculator).to have_received(:dependency_belongs_to_more_specific_group?).with(
          generic_group,
          docker_dep_minor_update,
          snapshot_with_multiple_groups.groups,
          instance_of(Proc),
          "/api",
          applies_to: nil,
          update_type: "minor"
        )
      end
    end

    describe "#partition_dependencies with specificity filtering" do
      let(:dependency_change) do
        create_dependency_change(
          job: job,
          dependencies: [docker_dep, nginx_dep, redis_dep],
          files: [create_dependency_file("Gemfile.lock", "/api")]
        )
      end

      context "when processing generic group that matches everything" do
        let(:generic_selector) do
          described_class.new(group: generic_group, dependency_snapshot: snapshot_with_multiple_groups)
        end

        before do
          allow(Dependabot::Experiments).to receive(:enabled?)
            .with(:group_membership_enforcement).and_return(true)

          [generic_group, docker_group, exact_group].each do |g|
            allow(g).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
            allow(g).to receive(:respond_to?).with(:applies_to).and_return(false)
          end

          allow(generic_group).to receive_messages(contains?: true, dependencies: [])
          allow(docker_group).to receive(:contains?) { |dep| dep.name.start_with?("docker") }
          allow(exact_group).to receive(:contains?) { |dep| dep.name == "nginx" }

          allow(job).to receive_messages(ignore_conditions_for: [], allowed_update?: true)

          allow(docker_group).to receive(:dependencies).and_return([])
          allow(exact_group).to receive(:dependencies).and_return([])
        end

        it "filters out dependencies that belong to more specific groups" do
          eligible_deps, filtered_deps = generic_selector.send(:partition_dependencies, dependency_change)

          eligible_names = eligible_deps.map(&:name)
          filtered_names = filtered_deps.map(&:name)

          expect(eligible_names).to contain_exactly("redis-client")
          expect(filtered_names).to include("docker-compose", "nginx")
        end

        it "annotates filtered dependencies with correct reason" do
          expect(Dependabot::DependencyAttribution).to receive(:annotate_dependency)
            .with(docker_dep, hash_including(selection_reason: :belongs_to_more_specific_group))
          expect(Dependabot::DependencyAttribution).to receive(:annotate_dependency)
            .with(nginx_dep, hash_including(selection_reason: :belongs_to_more_specific_group))
          expect(Dependabot::DependencyAttribution).to receive(:annotate_dependency)
            .with(redis_dep, hash_including(selection_reason: :direct))

          generic_selector.send(:partition_dependencies, dependency_change)
        end
      end

      context "when processing specific group" do
        let(:docker_selector) do
          described_class.new(group: docker_group, dependency_snapshot: snapshot_with_multiple_groups)
        end

        before do
          allow(Dependabot::Experiments).to receive(:enabled?)
            .with(:group_membership_enforcement).and_return(true)

          [generic_group, docker_group, exact_group].each do |g|
            allow(g).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
            allow(g).to receive(:respond_to?).with(:applies_to).and_return(false)
          end

          allow(generic_group).to receive_messages(contains?: true, dependencies: [])
          allow(docker_group).to receive(:contains?) { |dep| dep.name.start_with?("docker") }
          allow(exact_group).to receive(:contains?) { |dep| dep.name == "nginx" }

          allow(job).to receive_messages(ignore_conditions_for: [], allowed_update?: true)

          allow(generic_group).to receive(:dependencies).and_return([])
          allow(docker_group).to receive(:dependencies).and_return([])
          allow(exact_group).to receive(:dependencies).and_return([])
        end

        it "includes dependencies that match its specific pattern" do
          eligible_deps, filtered_deps = docker_selector.send(:partition_dependencies, dependency_change)

          eligible_names = eligible_deps.map(&:name)
          filtered_names = filtered_deps.map(&:name)

          expect(eligible_names).to contain_exactly("docker-compose")
          expect(filtered_names).to include("nginx", "redis-client")
        end
      end
    end

    describe "integration with filter_to_group!" do
      let(:dependency_change) do
        create_dependency_change(
          job: job,
          dependencies: [docker_dep, nginx_dep],
          files: [create_dependency_file("Gemfile.lock", "/api")]
        )
      end

      let(:generic_selector) do
        described_class.new(group: generic_group, dependency_snapshot: snapshot_with_multiple_groups)
      end

      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_membership_enforcement).and_return(true)

        [generic_group, docker_group, exact_group].each do |g|
          allow(g).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
          allow(g).to receive(:respond_to?).with(:applies_to).and_return(false)
        end

        allow(generic_group).to receive_messages(contains?: true, dependencies: [])
        allow(docker_group).to receive(:contains?) { |dep| dep.name.start_with?("docker") }
        allow(exact_group).to receive(:contains?) { |dep| dep.name == "nginx" }

        allow(job).to receive_messages(ignore_conditions_for: [], allowed_update?: true)

        allow(generic_group).to receive(:dependencies).and_return([])
        allow(docker_group).to receive(:dependencies).and_return([])
        allow(exact_group).to receive(:dependencies).and_return([])

        allow(dependency_change.updated_dependencies).to receive(:clear)
        allow(dependency_change.updated_dependencies).to receive(:concat)
      end

      it "logs dependencies filtered due to more specific groups" do
        expect(generic_selector).to receive(:log_filtered_dependencies) do |filtered_deps|
          expect(filtered_deps.length).to be > 0
        end

        generic_selector.filter_to_group!(dependency_change)
      end

      it "includes specificity filtering in group dependencies by reason" do
        allow(Dependabot::DependencyAttribution).to receive(:get_attribution) do |dep|
          if %w(docker-compose nginx).include?(dep.name)
            { selection_reason: :belongs_to_more_specific_group }
          else
            { selection_reason: :direct }
          end
        end

        filtered_deps = [docker_dep, nginx_dep]
        grouped = generic_selector.send(:group_dependencies_by_reason, filtered_deps)

        expect(grouped[:belongs_to_more_specific_group]).to contain_exactly("docker-compose", "nginx")
        expect(grouped[:not_in_group]).to be_empty
        expect(grouped[:filtered_by_config]).to be_empty
      end
    end

    describe "applies_to aware specificity" do
      let(:generic_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "all-dependencies",
          dependencies: [],
          applies_to: "version-updates",
          rules: { "patterns" => ["*"] }
        )
      end

      let(:security_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "security-dependencies",
          dependencies: [],
          applies_to: "security-updates",
          rules: { "patterns" => ["docker*"] }
        )
      end

      let(:snapshot_with_multiple_groups) do
        instance_double(
          Dependabot::DependencySnapshot,
          ecosystem: "bundler",
          groups: [generic_group, security_group]
        )
      end

      let(:generic_selector) do
        described_class.new(group: generic_group, dependency_snapshot: snapshot_with_multiple_groups)
      end

      let(:docker_dep) do
        Dependabot::Dependency.new(
          name: "docker-compose",
          package_manager: "bundler",
          version: "2.0.0",
          previous_version: "1.9.0",
          requirements: [
            { file: "Gemfile", requirement: "~> 2.0.0", groups: ["default"], source: nil }
          ],
          previous_requirements: [
            { file: "Gemfile", requirement: "~> 1.9.0", groups: ["default"], source: nil }
          ],
          directory: "/api",
          subdependency_metadata: [],
          removed: false,
          metadata: {}
        )
      end

      before do
        allow(Dependabot::Utils).to receive(:version_class_for_package_manager).and_return(Dependabot::Version)

        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_membership_enforcement).and_return(true)

        [generic_group, security_group].each do |g|
          allow(g).to receive(:respond_to?).with(:applies_to).and_return(true)
          allow(g).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
        end

        allow(generic_group).to receive_messages(contains?: true, dependencies: [])
        allow(security_group).to receive(:contains?) { |dep| dep.name.start_with?("docker") }
      end

      it "does not filter dependency when more specific group applies_to differs" do
        result = generic_selector.send(:dependency_belongs_to_more_specific_group?, docker_dep, "/api")
        expect(result).to be false
      end
    end

    context "with all group rule options" do
      let(:generic_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "generic",
          dependencies: [],
          applies_to: "version-updates",
          rules: { "patterns" => ["*"] }
        )
      end

      let(:docker_minor_prod_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "docker-minor-prod",
          dependencies: [],
          applies_to: "version-updates",
          rules: { "patterns" => ["docker*"], "update-types" => ["minor"], "dependency-type" => "production" }
        )
      end

      let(:docker_exact_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "docker-compose-exact",
          dependencies: [],
          applies_to: nil,
          rules: { "patterns" => ["docker-compose"], "update-types" => ["minor"] }
        )
      end

      let(:docker_security_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "docker-security",
          dependencies: [],
          applies_to: "security-updates",
          rules: { "patterns" => ["docker*"], "update-types" => ["minor"] }
        )
      end

      let(:excluded_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "docker-excluded",
          dependencies: [],
          applies_to: "version-updates",
          rules: { "patterns" => ["docker*"], "exclude-patterns" => ["docker-compose"] }
        )
      end

      let(:explicit_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "explicit",
          dependencies: [],
          applies_to: nil,
          rules: { "patterns" => [] }
        )
      end

      let(:snapshot) do
        instance_double(
          Dependabot::DependencySnapshot,
          ecosystem: "bundler",
          groups: [generic_group, docker_minor_prod_group, docker_exact_group, docker_security_group, excluded_group,
                   explicit_group]
        )
      end

      let(:generic_selector) { described_class.new(group: generic_group, dependency_snapshot: snapshot) }

      let(:docker_prod_minor_dep) { create_dependency("docker-compose", "2.1.0", metadata: { dep_type: "production" }) }
      let(:docker_dev_minor_dep) { create_dependency("docker-tool", "1.2.0", metadata: { dep_type: "development" }) }
      let(:docker_prod_major_dep) { create_dependency("docker-compose", "3.0.0", metadata: { dep_type: "production" }) }

      let(:dependency_change) do
        create_dependency_change(
          job: job,
          dependencies: [docker_prod_minor_dep, docker_dev_minor_dep, docker_prod_major_dep],
          files: [create_dependency_file("Gemfile.lock", "/api")]
        )
      end

      before do
        allow(Dependabot::Experiments).to receive(:enabled?).with(:group_membership_enforcement).and_return(true)

        [generic_group, docker_minor_prod_group, docker_exact_group, docker_security_group, excluded_group,
         explicit_group].each do |g|
          allow(g).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
          allow(g).to receive(:respond_to?).with(:applies_to).and_return(true)
        end

        allow(generic_group).to receive(:contains?).and_return(true)
        allow(docker_minor_prod_group).to receive(:contains?) do |dep|
          dep.name.start_with?("docker") && dep.respond_to?(:metadata) && dep.metadata[:dep_type] == "production"
        end
        allow(docker_exact_group).to receive(:contains?) { |dep| dep.name == "docker-compose" }
        allow(docker_security_group).to receive(:contains?) { |dep| dep.name.start_with?("docker") }
        allow(excluded_group).to receive(:contains?) { |dep| dep.name.start_with?("docker") }
        allow(explicit_group).to receive(:contains?) { |dep| dep == docker_dev_minor_dep }

        allow(docker_minor_prod_group).to receive(:dependencies).and_return([])
        allow(docker_exact_group).to receive(:dependencies).and_return([])
        allow(docker_security_group).to receive(:dependencies).and_return([])
        allow(excluded_group).to receive(:dependencies).and_return([])
        allow(explicit_group).to receive(:dependencies).and_return([docker_dev_minor_dep])

        allow(job).to receive_messages(ignore_conditions_for: [], allowed_update?: true)

        allow(generic_selector).to receive(:update_type_for_dependency) do |dep|
          case dep
          when docker_prod_minor_dep then "minor"
          when docker_dev_minor_dep then "minor"
          when docker_prod_major_dep then "major"
          end
        end
      end

      it "routes dependencies to more specific groups based on combined rules" do
        eligible_deps, filtered_deps = generic_selector.send(:partition_dependencies, dependency_change)

        # docker-compose v2.1.0 (minor update, production) → filtered to docker-compose-exact group
        # docker-compose v3.0.0 (major update, production) → stays in generic group (no matching specific group)
        # docker-tool (minor update, development) → filtered to explicit group

        # The major update of docker-compose stays eligible for generic group
        expect(eligible_deps).to include(docker_prod_major_dep)
        expect(eligible_deps.count { |d| d.name == "docker-compose" }).to eq(1)

        # The minor update of docker-compose is filtered to more specific group
        expect(filtered_deps).to include(docker_prod_minor_dep)

        # The development tool is filtered to explicit group
        expect(filtered_deps).to include(docker_dev_minor_dep)

        # Verify name-based summary
        eligible_names = eligible_deps.map(&:name)
        filtered_names = filtered_deps.map(&:name)

        expect(eligible_names).to eq(["docker-compose"])
        expect(filtered_names).to contain_exactly("docker-compose", "docker-tool")
      end
    end

    context "with complete multi-group interaction integration tests" do
      context "with complete routing through multiple competing groups" do
        let(:generic_group) do
          instance_double(
            Dependabot::DependencyGroup,
            name: "generic",
            dependencies: [],
            applies_to: "version-updates",
            rules: { "patterns" => ["*"] }
          )
        end

        let(:minor_updates_group) do
          instance_double(
            Dependabot::DependencyGroup,
            name: "minor-updates",
            dependencies: [],
            applies_to: "version-updates",
            rules: { "patterns" => ["*"], "update-types" => ["minor"] }
          )
        end

        let(:exact_rails_group) do
          instance_double(
            Dependabot::DependencyGroup,
            name: "exact-rails",
            dependencies: [],
            applies_to: "version-updates",
            rules: { "patterns" => ["rails"] }
          )
        end

        let(:snapshot) do
          instance_double(
            Dependabot::DependencySnapshot,
            ecosystem: "bundler",
            groups: [generic_group, minor_updates_group, exact_rails_group]
          )
        end

        let(:rails_minor) { create_dependency("rails", "7.1.0", previous_version: "7.0.0") }
        let(:axios_major) { create_dependency("axios", "2.0.0", previous_version: "1.5.0") }
        let(:lodash_patch) { create_dependency("lodash", "4.17.22", previous_version: "4.17.21") }
        let(:express_minor) { create_dependency("express", "5.1.0", previous_version: "5.0.0") }

        let(:dependency_change) do
          create_dependency_change(
            job: job,
            dependencies: [rails_minor, axios_major, lodash_patch, express_minor],
            files: [create_dependency_file("Gemfile.lock", "/")]
          )
        end

        before do
          allow(Dependabot::Experiments).to receive(:enabled?).with(:group_membership_enforcement).and_return(true)

          [generic_group, minor_updates_group, exact_rails_group].each do |g|
            allow(g).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
            allow(g).to receive(:respond_to?).with(:applies_to).and_return(true)
            allow(g).to receive_messages(dependencies: [], contains?: true)
          end

          allow(exact_rails_group).to receive(:contains?) { |dep| dep.name == "rails" }

          allow(job).to receive_messages(ignore_conditions_for: [], allowed_update?: true)
        end

        it "routes rails to exact-rails group (highest specificity)" do
          selector = described_class.new(group: generic_group, dependency_snapshot: snapshot)
          allow(selector).to receive(:update_type_for_dependency).and_return("minor")

          eligible_deps, filtered_deps = selector.send(:partition_dependencies, dependency_change)
          expect(filtered_deps.map(&:name)).to include("rails")
          expect(eligible_deps.map(&:name)).not_to include("rails")
        end

        it "demonstrates how update-types affects group selection priority" do
          selector = described_class.new(group: generic_group, dependency_snapshot: snapshot)
          allow(selector).to receive(:update_type_for_dependency) do |dep|
            case dep
            when rails_minor, express_minor then "minor"
            when lodash_patch then "patch"
            when axios_major then "major"
            end
          end

          eligible_deps, filtered_deps = selector.send(:partition_dependencies, dependency_change)
          expect(filtered_deps.map(&:name)).to include("rails")
          expect(eligible_deps.map(&:name)).to include("axios", "lodash", "express")
        end

        it "demonstrates complete multi-group routing behavior" do
          selectors = {
            generic: described_class.new(group: generic_group, dependency_snapshot: snapshot),
            minor_updates: described_class.new(group: minor_updates_group, dependency_snapshot: snapshot),
            exact_rails: described_class.new(group: exact_rails_group, dependency_snapshot: snapshot)
          }

          selectors.each_value do |selector|
            allow(selector).to receive(:update_type_for_dependency) do |dep|
              case dep
              when rails_minor, express_minor then "minor"
              when lodash_patch then "patch"
              when axios_major then "major"
              end
            end
          end

          results = selectors.transform_values do |selector|
            selector.send(:partition_dependencies, dependency_change).first.map(&:name)
          end

          expect(results[:exact_rails]).to contain_exactly("rails")
          expect(results[:minor_updates]).to include("express")
          expect(results[:generic]).to include("axios", "lodash")
        end
      end

      context "with applies_to filtering across version and security updates" do
        let(:version_generic_group) do
          instance_double(
            Dependabot::DependencyGroup,
            name: "version-generic",
            dependencies: [],
            applies_to: "version-updates",
            rules: { "patterns" => ["*"] }
          )
        end

        let(:security_rails_group) do
          instance_double(
            Dependabot::DependencyGroup,
            name: "security-rails",
            dependencies: [],
            applies_to: "security-updates",
            rules: { "patterns" => ["rails"] }
          )
        end

        let(:version_rails_group) do
          instance_double(
            Dependabot::DependencyGroup,
            name: "version-rails",
            dependencies: [],
            applies_to: "version-updates",
            rules: { "patterns" => ["rails"] }
          )
        end

        let(:snapshot) do
          instance_double(
            Dependabot::DependencySnapshot,
            ecosystem: "bundler",
            groups: [version_generic_group, security_rails_group, version_rails_group]
          )
        end

        let(:rails_dep) { create_dependency("rails", "7.1.0", previous_version: "7.0.0") }
        let(:axios_dep) { create_dependency("axios", "1.6.0", previous_version: "1.5.0") }
        let(:lodash_dep) { create_dependency("lodash", "4.17.22", previous_version: "4.17.21") }

        let(:dependency_change) do
          create_dependency_change(
            job: job,
            dependencies: [rails_dep, axios_dep, lodash_dep],
            files: [create_dependency_file("Gemfile.lock", "/")]
          )
        end

        before do
          allow(Dependabot::Experiments).to receive(:enabled?).with(:group_membership_enforcement).and_return(true)

          [version_generic_group, security_rails_group, version_rails_group].each do |g|
            allow(g).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
            allow(g).to receive(:respond_to?).with(:applies_to).and_return(true)
            allow(g).to receive_messages(dependencies: [], contains?: true)
          end

          allow(security_rails_group).to receive(:contains?) { |dep| dep.name == "rails" }
          allow(version_rails_group).to receive(:contains?) { |dep| dep.name == "rails" }

          allow(job).to receive_messages(ignore_conditions_for: [], allowed_update?: true)
        end

        it "prevents routing to security-updates group during version update run" do
          selector = described_class.new(group: version_generic_group, dependency_snapshot: snapshot)
          allow(selector).to receive(:update_type_for_dependency).and_return("minor")

          eligible_deps, filtered_deps = selector.send(:partition_dependencies, dependency_change)

          expect(filtered_deps.map(&:name)).to include("rails")
          expect(eligible_deps.map(&:name)).to include("axios", "lodash")
        end

        it "correctly applies applies_to filtering in specificity calculation" do
          version_generic_selector = described_class.new(group: version_generic_group, dependency_snapshot: snapshot)
          version_rails_selector = described_class.new(group: version_rails_group, dependency_snapshot: snapshot)

          [version_generic_selector, version_rails_selector].each do |selector|
            allow(selector).to receive(:update_type_for_dependency).and_return("minor")
          end

          generic_eligible = version_generic_selector.send(:partition_dependencies, dependency_change).first.map(&:name)
          rails_eligible = version_rails_selector.send(:partition_dependencies, dependency_change).first.map(&:name)

          expect(rails_eligible).to contain_exactly("rails")
          expect(generic_eligible).to contain_exactly("axios", "lodash")
        end
      end

      context "with explicit membership overriding pattern matching" do
        let(:generic_group) do
          instance_double(
            Dependabot::DependencyGroup,
            name: "generic",
            dependencies: [],
            applies_to: "version-updates",
            rules: { "patterns" => ["*"] }
          )
        end

        let(:express_explicit_group) do
          instance_double(
            Dependabot::DependencyGroup,
            name: "express-explicit",
            dependencies: ["express"],
            applies_to: "version-updates",
            rules: { "patterns" => [] }
          )
        end

        let(:prod_deps_group) do
          instance_double(
            Dependabot::DependencyGroup,
            name: "prod-deps",
            dependencies: [],
            applies_to: "version-updates",
            rules: { "patterns" => ["*"], "dependency-type" => "production" }
          )
        end

        let(:snapshot) do
          instance_double(
            Dependabot::DependencySnapshot,
            ecosystem: "bundler",
            groups: [generic_group, express_explicit_group, prod_deps_group]
          )
        end

        let(:rails_dep) do
          create_dependency("rails", "7.1.0", previous_version: "7.0.0", metadata: { dep_type: "production" })
        end
        let(:express_dep) do
          create_dependency("express", "5.1.0", previous_version: "5.0.0", metadata: { dep_type: "production" })
        end
        let(:axios_dep) do
          create_dependency("axios", "1.6.0", previous_version: "1.5.0", metadata: { dep_type: "development" })
        end
        let(:jest_dep) do
          create_dependency("jest", "30.0.0", previous_version: "29.0.0", metadata: { dep_type: "development" })
        end

        let(:dependency_change) do
          create_dependency_change(
            job: job,
            dependencies: [rails_dep, express_dep, axios_dep, jest_dep],
            files: [create_dependency_file("Gemfile.lock", "/")]
          )
        end

        before do
          allow(Dependabot::Experiments).to receive(:enabled?).with(:group_membership_enforcement).and_return(true)

          [generic_group, express_explicit_group, prod_deps_group].each do |g|
            allow(g).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
            allow(g).to receive(:respond_to?).with(:applies_to).and_return(true)
          end

          allow(generic_group).to receive_messages(dependencies: [], contains?: true)

          allow(express_explicit_group).to receive(:dependencies).and_return(["express"])
          allow(express_explicit_group).to receive(:contains?) { |dep| dep.name == "express" }

          allow(prod_deps_group).to receive(:dependencies).and_return([])
          allow(prod_deps_group).to receive(:contains?) do |dep|
            dep.respond_to?(:metadata) && dep.metadata[:dep_type] == "production"
          end

          allow(job).to receive_messages(ignore_conditions_for: [], allowed_update?: true)
        end

        it "routes express to explicit group despite matching other patterns" do
          generic_selector = described_class.new(group: generic_group, dependency_snapshot: snapshot)
          allow(generic_selector).to receive(:update_type_for_dependency).and_return("minor")
          allow(express_explicit_group).to receive(:dependencies).and_return([express_dep])

          eligible_deps, filtered_deps = generic_selector.send(:partition_dependencies, dependency_change)

          expect(filtered_deps.map(&:name)).to include("express")
          expect(eligible_deps.map(&:name)).not_to include("express")
        end

        it "routes express to explicit group even over more specific pattern matches" do
          prod_selector = described_class.new(group: prod_deps_group, dependency_snapshot: snapshot)
          allow(prod_selector).to receive(:update_type_for_dependency).and_return("minor")
          allow(express_explicit_group).to receive(:dependencies).and_return([express_dep])

          eligible_deps, filtered_deps = prod_selector.send(:partition_dependencies, dependency_change)

          expect(filtered_deps.map(&:name)).to include("express")
          expect(eligible_deps.map(&:name)).to include("rails")
          expect(eligible_deps.map(&:name)).not_to include("axios", "jest")
        end

        it "demonstrates explicit membership (specificity 1000) overrides all patterns" do
          selectors = {
            generic: described_class.new(group: generic_group, dependency_snapshot: snapshot),
            express_explicit: described_class.new(group: express_explicit_group, dependency_snapshot: snapshot),
            prod_deps: described_class.new(group: prod_deps_group, dependency_snapshot: snapshot)
          }

          selectors.each_value do |selector|
            allow(selector).to receive(:update_type_for_dependency).and_return("minor")
          end
          allow(express_explicit_group).to receive(:dependencies).and_return([express_dep])

          results = selectors.transform_values do |selector|
            selector.send(:partition_dependencies, dependency_change).first.map(&:name)
          end

          expect(results[:express_explicit]).to contain_exactly("express")
          expect(results[:prod_deps]).to contain_exactly("rails")
          expect(results[:generic]).to contain_exactly("rails", "axios", "jest")
        end
      end

      context "with update-type filtering splitting dependencies by version change magnitude" do
        let(:generic_group) do
          instance_double(
            Dependabot::DependencyGroup,
            name: "generic",
            dependencies: [],
            applies_to: "version-updates",
            rules: { "patterns" => ["*"] }
          )
        end

        let(:minor_patch_only_group) do
          instance_double(
            Dependabot::DependencyGroup,
            name: "minor-patch-only",
            dependencies: [],
            applies_to: "version-updates",
            rules: { "patterns" => ["*"], "update-types" => %w(minor patch) }
          )
        end

        let(:major_only_group) do
          instance_double(
            Dependabot::DependencyGroup,
            name: "major-only",
            dependencies: [],
            applies_to: "version-updates",
            rules: { "patterns" => ["*"], "update-types" => ["major"] }
          )
        end

        let(:snapshot) do
          instance_double(
            Dependabot::DependencySnapshot,
            ecosystem: "bundler",
            groups: [generic_group, minor_patch_only_group, major_only_group]
          )
        end

        let(:webpack_minor) { create_dependency("webpack", "5.89.0", previous_version: "5.88.0") }
        let(:babel_major) { create_dependency("babel", "8.0.0", previous_version: "7.23.0") }
        let(:react_minor) { create_dependency("react", "18.3.0", previous_version: "18.2.0") }
        let(:vue_patch) { create_dependency("vue", "3.4.28", previous_version: "3.4.27") }

        let(:dependency_change) do
          create_dependency_change(
            job: job,
            dependencies: [webpack_minor, babel_major, react_minor, vue_patch],
            files: [create_dependency_file("package.json", "/")]
          )
        end

        before do
          allow(Dependabot::Experiments).to receive(:enabled?).with(:group_membership_enforcement).and_return(true)

          [generic_group, minor_patch_only_group, major_only_group].each do |g|
            allow(g).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
            allow(g).to receive(:respond_to?).with(:applies_to).and_return(true)
            allow(g).to receive_messages(dependencies: [], contains?: true)
          end

          allow(job).to receive_messages(ignore_conditions_for: [], allowed_update?: true)
        end

        it "shows update-types filtering behavior with equal-specificity groups" do
          generic_selector = described_class.new(group: generic_group, dependency_snapshot: snapshot)
          allow(generic_selector).to receive(:update_type_for_dependency) do |dep|
            case dep
            when webpack_minor, react_minor then "minor"
            when vue_patch then "patch"
            when babel_major then "major"
            end
          end

          eligible_deps, = generic_selector.send(:partition_dependencies, dependency_change)

          expect(eligible_deps.map(&:name)).to include("webpack", "react", "vue", "babel")
        end

        it "demonstrates update-types affects competition but not specificity" do
          selectors = {
            generic: described_class.new(group: generic_group, dependency_snapshot: snapshot),
            minor_patch: described_class.new(group: minor_patch_only_group, dependency_snapshot: snapshot),
            major_only: described_class.new(group: major_only_group, dependency_snapshot: snapshot)
          }

          selectors.each_value do |selector|
            allow(selector).to receive(:update_type_for_dependency) do |dep|
              case dep
              when webpack_minor, react_minor then "minor"
              when vue_patch then "patch"
              when babel_major then "major"
              end
            end
          end

          results = selectors.transform_values do |selector|
            selector.send(:partition_dependencies, dependency_change).first.map(&:name)
          end

          expect(results[:minor_patch]).to include("webpack", "react", "vue")
          expect(results[:major_only]).to include("babel")
          expect(results[:generic]).to include("webpack", "react", "vue", "babel")
        end
      end

      context "with exclude-patterns affecting specificity routing" do
        let(:generic_group) do
          instance_double(
            Dependabot::DependencyGroup,
            name: "generic",
            dependencies: [],
            applies_to: "version-updates",
            rules: { "patterns" => ["*"] }
          )
        end

        let(:rails_except_test_group) do
          instance_double(
            Dependabot::DependencyGroup,
            name: "rails-except-test",
            dependencies: [],
            applies_to: "version-updates",
            rules: { "patterns" => ["rails*"], "exclude-patterns" => ["*-test"] }
          )
        end

        let(:snapshot) do
          instance_double(
            Dependabot::DependencySnapshot,
            ecosystem: "bundler",
            groups: [generic_group, rails_except_test_group]
          )
        end

        let(:rails_test) { create_dependency("rails-test", "1.2.0", previous_version: "1.1.0") }
        let(:rails_helper) { create_dependency("rails-helper", "2.1.0", previous_version: "2.0.0") }
        let(:rails_core) { create_dependency("rails", "7.1.0", previous_version: "7.0.0") }

        let(:dependency_change) do
          create_dependency_change(
            job: job,
            dependencies: [rails_test, rails_helper, rails_core],
            files: [create_dependency_file("Gemfile.lock", "/")]
          )
        end

        before do
          allow(Dependabot::Experiments).to receive(:enabled?).with(:group_membership_enforcement).and_return(true)

          [generic_group, rails_except_test_group].each do |g|
            allow(g).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
            allow(g).to receive(:respond_to?).with(:applies_to).and_return(true)
            allow(g).to receive(:dependencies).and_return([])
          end

          allow(generic_group).to receive(:contains?).and_return(true)
          allow(rails_except_test_group).to receive(:contains?) do |dep|
            dep.name.start_with?("rails") && !dep.name.end_with?("-test")
          end

          allow(job).to receive_messages(ignore_conditions_for: [], allowed_update?: true)
        end

        it "keeps rails-test in generic group due to exclusion pattern" do
          generic_selector = described_class.new(group: generic_group, dependency_snapshot: snapshot)
          allow(generic_selector).to receive(:update_type_for_dependency).and_return("minor")

          eligible_deps, filtered_deps = generic_selector.send(:partition_dependencies, dependency_change)

          expect(eligible_deps.map(&:name)).to include("rails-test")
          expect(filtered_deps.map(&:name)).to include("rails-helper", "rails")
        end

        it "demonstrates exclude-patterns removing matches from specificity calculation" do
          selectors = {
            generic: described_class.new(group: generic_group, dependency_snapshot: snapshot),
            rails_except_test: described_class.new(group: rails_except_test_group, dependency_snapshot: snapshot)
          }

          selectors.each_value do |selector|
            allow(selector).to receive(:update_type_for_dependency).and_return("minor")
          end

          results = selectors.transform_values do |selector|
            selector.send(:partition_dependencies, dependency_change).first.map(&:name)
          end

          expect(results[:rails_except_test]).to contain_exactly("rails-helper", "rails")
          expect(results[:generic]).to contain_exactly("rails-test")
        end
      end
    end
  end

  private

  def create_dependency(
    name,
    version,
    previous_version: nil,
    metadata: {},
    package_manager: "bundler",
    requirements: [],
    directory: "/api"
  )
    requirements = default_requirements_for(version, metadata) if requirements.empty?

    build_dependency_double(
      name: name,
      version: version,
      previous_version: previous_version,
      metadata: metadata,
      package_manager: package_manager,
      requirements: requirements,
      directory: directory
    )
  end

  def default_requirements_for(version, metadata)
    groups = metadata.is_a?(Hash) && metadata[:dep_type] == "development" ? ["development"] : ["default"]

    [{
      file: "Gemfile",
      requirement: "~> #{version}",
      groups: groups,
      source: nil
    }]
  end

  def build_dependency_double(
    name:,
    version:,
    previous_version:,
    metadata:,
    package_manager:,
    requirements:,
    directory:
  )
    instance_double(
      Dependabot::Dependency,
      name: name,
      version: version,
      previous_version: previous_version,
      metadata: metadata,
      package_manager: package_manager,
      requirements: requirements,
      directory: directory
    ).tap do |dep|
      stub_production_check(dep, requirements)
      stub_attribution_methods(dep)
    end
  end

  def stub_production_check(dep, requirements)
    allow(dep).to receive(:production?) do
      groups = requirements.flat_map { |r| r.fetch(:groups, []).map(&:to_s) }

      groups.empty? || groups.include?("runtime") || groups.include?("default") || groups.any? do |g|
        g.include?("prod")
      end
    end
  end

  def stub_attribution_methods(dep)
    allow(dep).to receive(:attribution_source_group=)
    allow(dep).to receive(:attribution_selection_reason=)
    allow(dep).to receive(:attribution_directory=)
    allow(dep).to receive(:attribution_timestamp=)
    allow(dep).to receive_messages(
      attribution_source_group: nil,
      attribution_selection_reason: nil,
      attribution_directory: nil,
      attribution_timestamp: nil
    )
  end

  def create_dependency_change(job:, dependencies:, files:)
    instance_double(
      Dependabot::DependencyChange,
      job: job,
      updated_dependencies: dependencies,
      updated_dependency_files: files
    ).tap do |change|
      allow(change.updated_dependencies).to receive(:clear)
      allow(change.updated_dependencies).to receive(:concat)
    end
  end

  def create_dependency_file(name, directory)
    instance_double(
      Dependabot::DependencyFile,
      name: name,
      directory: directory
    )
  end

  def create_job(directory)
    instance_double(
      Dependabot::Job,
      source: instance_double(Dependabot::Source, directory: directory)
    )
  end
end
