const path = require("path");
const os = require("os");
const fs = require("fs");
const helpers = require("./helpers");

// Import the actual function we're testing
const subdependencyUpdater = require("../../lib/npm8/subdependency-updater");

describe("npm8 subdependency-updater", () => {
  describe("removeDependenciesFromLockfile", () => {
    it("removes subdependency package entries from lockfile", () => {
      const lockfile = {
        name: "test",
        version: "1.0.0",
        lockfileVersion: 2,
        packages: {
          "": {
            version: "1.0.0",
            dependencies: {
              axios: "^1.0.0",
            },
          },
          "node_modules/axios": {
            version: "1.0.0",
            dependencies: {
              "follow-redirects": "^1.14.4",
            },
          },
          "node_modules/follow-redirects": {
            version: "1.14.4",
          },
        },
      };

      // Use the internal function through module exports
      // We'll need to expose it for testing
      const result = subdependencyUpdater.removeDependenciesFromLockfile(
        lockfile,
        ["follow-redirects"]
      );

      // follow-redirects package entry should be removed
      expect(result.packages["node_modules/follow-redirects"]).toBeUndefined();

      // axios should still be there
      expect(result.packages["node_modules/axios"]).toBeDefined();

      // axios's dependency reference should still be there
      expect(
        result.packages["node_modules/axios"].dependencies["follow-redirects"]
      ).toBe("^1.14.4");
    });

    it("handles scoped packages", () => {
      const lockfile = {
        name: "test",
        version: "1.0.0",
        lockfileVersion: 2,
        packages: {
          "": {
            version: "1.0.0",
            dependencies: {
              "@scope/package": "^1.0.0",
            },
          },
          "node_modules/@scope/package": {
            version: "1.0.0",
          },
        },
      };

      const result = subdependencyUpdater.removeDependenciesFromLockfile(
        lockfile,
        ["@scope/package"]
      );

      expect(result.packages["node_modules/@scope/package"]).toBeUndefined();
      expect(result.packages[""]).toBeDefined();
    });
  });
});
