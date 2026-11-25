use serde_json::{Value, json};
use std::io::Write;
use std::process::{Command, Stdio};

fn invoke(request: Value) -> (bool, Value) {
    let mut child = Command::new(env!("CARGO_BIN_EXE_dependabot-cargo-lock-graph"))
        .env("PATH", "")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(request.to_string().as_bytes())
        .unwrap();
    let output = child.wait_with_output().unwrap();
    (
        output.status.success(),
        serde_json::from_slice(&output.stdout).unwrap(),
    )
}

fn facts(content: &str) -> Value {
    let (success, response) = invoke(json!({
        "function": "lock_graph",
        "args": [[{"name": "before", "content": content}]]
    }));
    assert!(success, "{response}");
    assert_eq!(response["result"]["schema_version"], 1);
    response["result"]["snapshots"][0].clone()
}

#[test]
fn resolves_compact_and_source_qualified_edges_without_cargo() {
    let result = facts(include_str!("fixtures/sources.lock"));
    assert_eq!(result["complete"], true);
    assert_eq!(result["lockfile_version"], 4);
    assert_eq!(result["packages"].as_array().unwrap().len(), 6);
    let edges = result["edges"].as_array().unwrap();
    assert_eq!(edges.len(), 5);
    assert!(edges.iter().any(|edge| {
        edge["to"]["source"]
            == "git+https://example.com/repo?branch=next#0123456789012345678901234567890123456789"
    }));
    assert!(edges.iter().any(|edge| edge["to"]["source"].is_null()));
    assert!(edges.iter().any(|edge| edge["to"]["version"] == "2.0.0"));
    assert!(
        edges
            .iter()
            .any(|edge| { edge["to"]["source"] == "sparse+https://example.com/index/" })
    );
}

#[test]
fn never_chooses_the_first_ambiguous_package() {
    for reference in ["shared", "shared 1.0.0"] {
        let content = include_str!("fixtures/sources.lock").replace(
            "shared 1.0.0 (registry+https://example.com/index)",
            reference,
        );
        let result = facts(&content);
        assert_eq!(result["complete"], false);
        assert_eq!(result["edges"].as_array().unwrap().len(), 4);
        assert_eq!(result["diagnostics"][0]["code"], "ambiguous_dependency");
        assert!(
            result["diagnostics"][0]["candidates"]
                .as_array()
                .unwrap()
                .len()
                >= 2
        );
    }
}

#[test]
fn handles_all_supported_formats_and_legacy_root() {
    let legacy = r#"
[root]
name = "app"
version = "0.1.0"
dependencies = ["dep 1.0.0 (registry+https://example.com/index)"]

[[package]]
name = "dep"
version = "1.0.0"
source = "registry+https://example.com/index"

[metadata]
"checksum dep 1.0.0 (registry+https://example.com/index)" = "<none>"
"#;
    let result = facts(legacy);
    assert_eq!(result["lockfile_version"], 1);
    assert_eq!(result["complete"], true);
    assert_eq!(result["packages"].as_array().unwrap().len(), 2);
    assert_eq!(result["edges"].as_array().unwrap().len(), 1);
    for version in [2, 3, 4] {
        let content = format!(
            "version = {version}\n[[package]]\nname = \"app\"\nversion = \"0.1.0\"\n\
             dependencies = [\"dep\"]\n[[package]]\nname = \"dep\"\nversion = \"1.0.0\"\n"
        );
        let result = facts(&content);
        assert_eq!(result["lockfile_version"], version);
        assert_eq!(result["complete"], true);
        assert_eq!(result["edges"].as_array().unwrap().len(), 1);
    }
}

#[test]
fn reports_missing_and_duplicate_identities() {
    let missing = facts(
        "version = 3\n[[package]]\nname = \"app\"\nversion = \"0.1.0\"\n\
         dependencies = [\"missing 1.0.0\"]\n",
    );
    assert_eq!(missing["complete"], false);
    assert_eq!(missing["diagnostics"][0]["code"], "unresolved_dependency");
    assert_eq!(missing["edges"], json!([]));
    let package = "[[package]]\nname = \"app\"\nversion = \"0.1.0\"\n";
    let duplicate = facts(&format!("version = 3\n{package}{package}"));
    assert_eq!(duplicate["complete"], false);
    assert_eq!(duplicate["diagnostics"][0]["code"], "duplicate_package");
}

#[test]
fn preserves_explicit_path_and_git_reference_identity() {
    let result = facts(
        "version = 4\n[[package]]\nname = \"app\"\nversion = \"0.1.0\"\n\
         dependencies = [\"local\", \"gitdep 1.0.0 (git+https://example.com/repo?tag=v1)\"]\n\
         [[package]]\nname = \"local\"\nversion = \"1.0.0\"\nsource = \"path+file:///tmp/local\"\n\
         [[package]]\nname = \"gitdep\"\nversion = \"1.0.0\"\n\
         source = \"git+https://example.com/repo?branch=next#aaaa\"\n",
    );
    assert_eq!(result["complete"], false);
    assert_eq!(result["edges"].as_array().unwrap().len(), 1);
    assert_eq!(result["edges"][0]["to"]["source"], "path+file:///tmp/local");
    assert_eq!(result["diagnostics"][0]["code"], "unresolved_dependency");
}

#[test]
fn keeps_batch_failures_local_and_rejects_bad_protocol() {
    let (success, response) = invoke(json!({
        "function": "lock_graph",
        "args": [[
            {"name": "after", "content": "version = 99"},
            {"name": "before", "content": include_str!("fixtures/sources.lock")}
        ]]
    }));
    assert!(success);
    assert_eq!(response["result"]["snapshots"][0]["name"], "after");
    assert_eq!(response["result"]["snapshots"][0]["complete"], false);
    assert_eq!(
        response["result"]["snapshots"][0]["diagnostics"][0]["code"],
        "parse_error"
    );
    assert_eq!(response["result"]["snapshots"][1]["complete"], true);
    let (success, response) = invoke(json!({"function": "other", "args": []}));
    assert!(!success);
    assert!(response["error"].is_string());
}

#[test]
fn output_is_independent_of_package_and_dependency_order() {
    let content = include_str!("fixtures/sources.lock");
    let mut chunks: Vec<_> = content.split("[[package]]").skip(1).collect();
    chunks.reverse();
    let reversed = format!("version = 4\n[[package]]{}", chunks.join("[[package]]"));
    let reversed = reversed.replace(
        " \"local\",\n \"shared 1.0.0 (registry+https://example.com/index)\",",
        " \"shared 1.0.0 (registry+https://example.com/index)\",\n \"local\",",
    );
    assert_eq!(facts(content), facts(&reversed));
}

#[test]
fn preserves_raw_git_spelling_and_replacement_edges() {
    let content = r#"
version = 4
[[package]]
name = "original"
version = "1.0.0"
source = "registry+https://example.com/index"
replace = "patched 1.0.0 (git+https://example.com/repo?branch=feature%2Fnext)"

[[package]]
name = "patched"
version = "1.0.0"
source = "git+https://example.com/repo?branch=feature%2Fnext#0123456789012345678901234567890123456789"
"#;
    let result = facts(content);
    assert_eq!(result["complete"], true);
    assert_eq!(result["edges"][0]["kind"], "replacement");
    assert_eq!(
        result["edges"][0]["to"]["source"],
        "git+https://example.com/repo?branch=feature%2Fnext#0123456789012345678901234567890123456789"
    );
    let ambiguous = format!(
        "{content}\n[[package]]\nname = \"patched\"\nversion = \"1.0.0\"\n\
         source = \"git+https://example.com/repo?branch=feature%2Fnext#aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"\n"
    );
    assert_eq!(facts(&ambiguous)["complete"], false);
    assert_eq!(
        facts(&ambiguous)["diagnostics"][0]["code"],
        "ambiguous_dependency"
    );
}

#[test]
fn rejects_duplicate_snapshot_names_and_orders_valid_batches() {
    let snapshot = json!({"name": "before", "content": include_str!("fixtures/sources.lock")});
    let (success, response) = invoke(json!({
        "function": "lock_graph",
        "args": [[snapshot, snapshot]]
    }));
    assert!(!success);
    assert_eq!(response["error_class"], "CargoLockGraphProtocolError");
    let after = json!({"name": "after", "content": include_str!("fixtures/sources.lock")});
    let (_, first) = invoke(json!({"function": "lock_graph", "args": [[snapshot, after]]}));
    let (_, second) = invoke(json!({"function": "lock_graph", "args": [[after, snapshot]]}));
    assert_eq!(first, second);
}
