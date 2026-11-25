use cargo_lock::{Lockfile, SourceId};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read, Write};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    function: String,
    args: [Vec<Snapshot>; 1],
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Snapshot {
    name: String,
    content: String,
}

#[derive(Serialize)]
struct Facts {
    schema_version: u32,
    snapshots: Vec<SnapshotFacts>,
}

#[derive(Serialize)]
struct SnapshotFacts {
    name: String,
    lockfile_version: Option<u32>,
    complete: bool,
    packages: Vec<PackageId>,
    edges: BTreeSet<Edge>,
    diagnostics: Vec<Diagnostic>,
}

#[derive(Clone, Deserialize, Serialize, PartialEq, Eq, PartialOrd, Ord)]
struct PackageId {
    name: String,
    version: String,
    source: Option<String>,
}

#[derive(Serialize, PartialEq, Eq, PartialOrd, Ord)]
struct Edge {
    from: PackageId,
    to: PackageId,
    kind: &'static str,
}

#[derive(Serialize, PartialEq, Eq, PartialOrd, Ord)]
struct Diagnostic {
    code: &'static str,
    message: String,
    package: Option<PackageId>,
    reference: Option<String>,
    candidates: Vec<PackageId>,
}

#[derive(Deserialize)]
struct RawLockfile {
    #[serde(default)]
    package: Vec<RawPackage>,
    root: Option<RawPackage>,
}

#[derive(Deserialize)]
struct RawPackage {
    #[serde(flatten)]
    id: PackageId,
    #[serde(default)]
    dependencies: Vec<String>,
    replace: Option<String>,
}

struct Reference {
    name: String,
    version: Option<String>,
    source: Option<SourceId>,
}

impl Reference {
    fn parse(raw: &str) -> Result<Self, String> {
        let (identity, source) = match raw.split_once(" (") {
            Some((identity, source)) => (
                identity,
                Some(
                    source
                        .strip_suffix(')')
                        .ok_or_else(|| "invalid source reference".to_string())?
                        .parse::<SourceId>()
                        .map_err(|error| error.to_string())?,
                ),
            ),
            None => (raw, None),
        };
        let (name, version) = match identity.split_once(' ') {
            Some((name, version)) => (
                name,
                Some(
                    version
                        .parse::<cargo_lock::Version>()
                        .map_err(|error| error.to_string())?
                        .to_string(),
                ),
            ),
            None => (identity, None),
        };
        let name = name
            .parse::<cargo_lock::Name>()
            .map_err(|error| error.to_string())?
            .to_string();
        Ok(Self {
            name,
            version,
            source,
        })
    }

    fn matches(&self, package: &PackageId, version: u32) -> bool {
        if self.name != package.name
            || self
                .version
                .as_ref()
                .is_some_and(|value| *value != package.version)
        {
            return false;
        }
        match (&self.source, &package.source) {
            (None, _) if version > 1 => true,
            (None, None) => true,
            (Some(reference), Some(raw_source)) => {
                let Ok(source) = raw_source.parse::<SourceId>() else {
                    return false;
                };
                // SourceId equality alone can collapse distinct Git selectors.
                reference.url() == source.url()
                    && reference.kind() == source.kind()
                    && (reference.precise().is_none() || reference.precise() == source.precise())
            }
            _ => false,
        }
    }
}

fn snapshot_facts(snapshot: Snapshot) -> SnapshotFacts {
    let mut facts = SnapshotFacts {
        name: snapshot.name,
        lockfile_version: None,
        complete: false,
        packages: Vec::new(),
        edges: BTreeSet::new(),
        diagnostics: Vec::new(),
    };
    let parsed = snapshot.content.parse::<Lockfile>();
    let raw = toml::from_str::<RawLockfile>(&snapshot.content);
    let (lockfile, raw) = match (parsed, raw) {
        (Ok(lockfile), Ok(raw)) => (lockfile, raw),
        (parsed, raw) => {
            let message = match (parsed, raw) {
                (Err(error), _) => error.to_string(),
                (_, Err(error)) => error.to_string(),
                _ => unreachable!(),
            };
            facts.diagnostics.push(Diagnostic {
                code: "parse_error",
                message,
                package: None,
                reference: None,
                candidates: Vec::new(),
            });
            return facts;
        }
    };
    let version = u32::from(lockfile.version);
    facts.lockfile_version = Some(version);
    // The raw view retains source spelling and abbreviated references which the
    // cargo-lock view normalizes (and may resolve by choosing the first match).
    let mut packages = raw.package;
    packages.extend(raw.root);
    for package in &mut packages {
        match package.id.version.parse::<cargo_lock::Version>() {
            Ok(version) => package.id.version = version.to_string(),
            Err(error) => {
                facts.diagnostics.push(Diagnostic {
                    code: "parse_error",
                    message: error.to_string(),
                    package: Some(package.id.clone()),
                    reference: None,
                    candidates: Vec::new(),
                });
            }
        }
    }
    let mut counts = BTreeMap::new();
    for package in &packages {
        *counts.entry(package.id.clone()).or_insert(0) += 1;
    }
    facts.packages = counts.keys().cloned().collect();
    for (package, count) in &counts {
        if *count > 1 {
            facts.diagnostics.push(Diagnostic {
                code: "duplicate_package",
                message: format!("package identity appears {count} times"),
                package: Some(package.clone()),
                reference: None,
                candidates: Vec::new(),
            });
        }
    }
    for package in &packages {
        for reference in &package.dependencies {
            resolve_edge(
                &mut facts,
                &counts,
                &package.id,
                reference,
                "dependency",
                version,
            );
        }
        if let Some(reference) = &package.replace {
            resolve_edge(
                &mut facts,
                &counts,
                &package.id,
                reference,
                "replacement",
                version,
            );
        }
    }
    facts.diagnostics.sort();
    facts.diagnostics.dedup();
    facts.complete = facts.diagnostics.is_empty();
    facts
}

fn resolve_edge(
    facts: &mut SnapshotFacts,
    counts: &BTreeMap<PackageId, usize>,
    from: &PackageId,
    raw: &str,
    kind: &'static str,
    version: u32,
) {
    let reference = match Reference::parse(raw) {
        Ok(reference) => reference,
        Err(message) => {
            facts.diagnostics.push(Diagnostic {
                code: "invalid_dependency",
                message,
                package: Some(from.clone()),
                reference: Some(raw.to_string()),
                candidates: Vec::new(),
            });
            return;
        }
    };
    let candidates: Vec<_> = counts
        .keys()
        .filter(|package| reference.matches(package, version))
        .cloned()
        .collect();
    if candidates.len() == 1 && counts[&candidates[0]] == 1 && counts[from] == 1 {
        facts.edges.insert(Edge {
            from: from.clone(),
            to: candidates[0].clone(),
            kind,
        });
    } else {
        let code = if candidates.is_empty() {
            "unresolved_dependency"
        } else {
            "ambiguous_dependency"
        };
        facts.diagnostics.push(Diagnostic {
            code,
            message: "reference must identify exactly one package entry".to_string(),
            package: Some(from.clone()),
            reference: Some(raw.to_string()),
            candidates,
        });
    }
}

fn run() -> Result<Facts, String> {
    let mut input = String::new();
    io::stdin()
        .read_to_string(&mut input)
        .map_err(|error| error.to_string())?;
    let request: Request = serde_json::from_str(&input).map_err(|error| error.to_string())?;
    if request.function != "lock_graph" {
        return Err(format!("unknown function: {}", request.function));
    }
    let [snapshots] = request.args;
    let mut names = BTreeSet::new();
    for snapshot in &snapshots {
        if snapshot.name.is_empty() || !names.insert(&snapshot.name) {
            return Err("snapshot names must be nonempty and unique".to_string());
        }
    }
    let mut snapshots: Vec<_> = snapshots.into_iter().map(snapshot_facts).collect();
    snapshots.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(Facts {
        schema_version: 1,
        snapshots,
    })
}

fn main() {
    let (response, success) = match run() {
        Ok(facts) => (serde_json::json!({ "result": facts }), true),
        Err(error) => (
            serde_json::json!({ "error": error, "error_class": "CargoLockGraphProtocolError" }),
            false,
        ),
    };
    if serde_json::to_writer(io::stdout().lock(), &response).is_err()
        || io::stdout().write_all(b"\n").is_err()
    {
        std::process::exit(1);
    }
    if !success {
        std::process::exit(1);
    }
}
