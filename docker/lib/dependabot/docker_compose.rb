# typed: true
# frozen_string_literal: true

Dependabot::PullRequestCreator::Labeler
  .register_label_details("docker_compose", name: "docker", colour: "21ceff")

Dependabot::Dependency.register_production_check(
  "docker_compose",
  ->(_) { true }
)
