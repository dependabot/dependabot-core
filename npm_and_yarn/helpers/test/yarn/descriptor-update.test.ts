import fs from "fs";
import os from "os";
import path from "path";
import http from "http";
import { execFile, execFileSync } from "child_process";
import { promisify } from "util";
import { parseNormalized } from "../../lib/yarn/lockfile-parser.js";

const execute = promisify(execFile);

interface PackageFixture {
  name: string;
  version: string;
  dependencies?: Record<string, string>;
}

it.each(["^2.0.2", ">=2.0.2 <3"])(
  "updates only the selected Yarn descriptor for %s using the Ruby updater",
  async (requirement) => {
    const directory = fs.mkdtempSync(
      path.join(os.tmpdir(), "yarn-descriptor-")
    );
    const packages: PackageFixture[] = [
      {
        name: "legacy-parent",
        version: "1.0.0",
        dependencies: { "brace-expansion": "^1.1.7" },
      },
      {
        name: "current-parent",
        version: "1.0.0",
        dependencies: { "brace-expansion": requirement },
      },
      {
        name: "modern-parent",
        version: "1.0.0",
        dependencies: { "brace-expansion": "^5.0.2" },
      },
      ...["1.1.12", "1.1.18", "2.1.2", "2.1.4", "2.1.5", "5.0.2", "5.0.12"].map(
        (version) => ({ name: "brace-expansion", version })
      ),
    ];
    const tarballs = new Map<string, Buffer>();
    const requests: string[] = [];
    let patchedVersionsAvailable = false;

    for (const pkg of packages) {
      const packageDirectory = path.join(
        directory,
        `${pkg.name}-${pkg.version}`,
        "package"
      );
      fs.mkdirSync(packageDirectory, { recursive: true });
      fs.writeFileSync(
        path.join(packageDirectory, "package.json"),
        JSON.stringify(pkg)
      );
      const tarball = path.join(directory, `${pkg.name}-${pkg.version}.tgz`);
      execFileSync("tar", [
        "-czf",
        tarball,
        "-C",
        path.dirname(packageDirectory),
        "package",
      ]);
      tarballs.set(
        `/${pkg.name}/-/${pkg.name}-${pkg.version}.tgz`,
        fs.readFileSync(tarball)
      );
    }

    const server = http.createServer((request, response) => {
      const requestPath = request.url ?? "/";
      requests.push(requestPath);
      const tarball = tarballs.get(requestPath);
      if (tarball) {
        response.end(tarball);
        return;
      }

      const releases = packages.filter(
        (pkg) =>
          `/${pkg.name}` === requestPath &&
          (pkg.name !== "brace-expansion" ||
            patchedVersionsAvailable ||
            ["1.1.12", "2.1.2", "5.0.2"].includes(pkg.version))
      );
      if (releases.length === 0) {
        response.writeHead(404).end(`Unknown fixture package: ${requestPath}`);
        return;
      }

      response.setHeader("Content-Type", "application/json");
      response.end(
        JSON.stringify({
          name: releases[0].name,
          "dist-tags": { latest: releases[releases.length - 1].version },
          time: Object.fromEntries(
            releases.map((pkg) => [pkg.version, "2020-01-01T00:00:00.000Z"])
          ),
          versions: Object.fromEntries(
            releases.map((pkg) => [
              pkg.version,
              {
                ...pkg,
                dist: {
                  tarball: `http://${request.headers.host}/${pkg.name}/-/${pkg.name}-${pkg.version}.tgz`,
                },
              },
            ])
          ),
        })
      );
    });

    try {
      await new Promise<void>((resolve) =>
        server.listen(0, "127.0.0.1", resolve)
      );
      const address = server.address();
      if (!address || typeof address === "string")
        throw new Error("Fixture registry did not bind a TCP port");

      const project = path.join(directory, "project");
      fs.mkdirSync(project);
      fs.copyFileSync(
        path.join(
          __dirname,
          "fixtures/conflicting-dependency-parser/multiple-versions/package.json"
        ),
        path.join(project, "package.json")
      );
      const runCommand = async (command: string, args: string[]) => {
        try {
          return await execute(command, args, {
            cwd: project,
            env: {
              ...process.env,
              BUNDLE_GEMFILE: "/home/dependabot/dependabot-updater/Gemfile",
              COREPACK_ENABLE_AUTO_PIN: "0",
              COREPACK_ENABLE_NETWORK: "0",
              YARN_NPM_REGISTRY_SERVER: `http://127.0.0.1:${address.port}`,
              YARN_UNSAFE_HTTP_WHITELIST: "127.0.0.1",
              YARN_ENABLE_TELEMETRY: "0",
              YARN_ENABLE_SCRIPTS: "0",
              YARN_ENABLE_GLOBAL_CACHE: "0",
              YARN_GLOBAL_FOLDER: path.join(directory, "global"),
              YARN_ENABLE_IMMUTABLE_INSTALLS: "0",
              YARN_NPM_MINIMAL_AGE_GATE: "0",
            },
          });
        } catch (error) {
          if (
            typeof error === "object" &&
            error !== null &&
            "message" in error &&
            "stdout" in error &&
            typeof error.stdout === "string"
          ) {
            throw new Error(`${error.message}\n${error.stdout}`, {
              cause: error,
            });
          }
          throw error;
        }
      };
      const runYarn = (...args: string[]) =>
        runCommand("corepack", ["yarn", ...args]);

      await runYarn("install", "--mode=update-lockfile");
      const manifest = fs.readFileSync(
        path.join(project, "package.json"),
        "utf8"
      );
      requests.length = 0;
      fs.rmSync(path.join(project, ".yarn"), { recursive: true, force: true });
      fs.rmSync(path.join(directory, "global", "cache"), {
        recursive: true,
        force: true,
      });
      patchedVersionsAvailable = true;
      await runCommand("bundle", [
        "exec",
        "ruby",
        "-I/home/dependabot/npm_and_yarn/lib",
        "-e",
        `
        require "dependabot/npm_and_yarn/file_updater/berry_lockfile_handler"
        dependency = Dependabot::Dependency.new(
          name: "brace-expansion", version: "2.1.2",
          requirements: [], package_manager: "npm_and_yarn"
        )
        Dependabot::NpmAndYarn::FileUpdater::BerryLockfileHandler.update_subdependency(
          yarn_lock: Dependabot::DependencyFile.new(name: "yarn.lock", content: File.read("yarn.lock")),
          dependency: dependency, target_version: "2.1.4",
          env: { "YARN_NPM_MINIMAL_AGE_GATE" => "0" }
        )
      `,
      ]);

      const entries = (await parseNormalized(project)).filter(
        (entry) => entry.name === "brace-expansion"
      );
      expect(
        entries.map(({ requirement, version }) => ({ requirement, version }))
      ).toEqual(
        expect.arrayContaining([
          { requirement: "^1.1.7", version: "1.1.12" },
          { requirement, version: "2.1.4" },
          { requirement: "^5.0.2", version: "5.0.2" },
        ])
      );
      expect(entries).toHaveLength(3);
      expect(requests).not.toContain(
        "/brace-expansion/-/brace-expansion-1.1.18.tgz"
      );
      expect(requests).not.toContain(
        "/brace-expansion/-/brace-expansion-5.0.12.tgz"
      );
      expect(requests.filter((request) => request.endsWith(".tgz"))).toEqual([
        "/brace-expansion/-/brace-expansion-2.1.4.tgz",
      ]);
      expect(fs.readFileSync(path.join(project, "package.json"), "utf8")).toBe(
        manifest
      );
    } finally {
      await new Promise<void>((resolve, reject) =>
        server.close((error) => (error ? reject(error) : resolve()))
      );
      fs.rmSync(directory, { recursive: true, force: true });
    }
  },
  60_000
);
