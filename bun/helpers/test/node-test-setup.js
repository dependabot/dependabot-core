const assert = require("node:assert/strict");
const {
  afterEach,
  beforeEach,
  describe,
  it,
  test,
} = require("node:test");

global.afterEach = afterEach;
global.beforeEach = beforeEach;
global.describe = describe;
global.fdescribe = describe;
global.it = it;
global.test = test;
global.expect = (actual) => ({
  not: {
    toBeNull: () => assert.notStrictEqual(actual, null),
    toContain: (expected) => assert.ok(!actual.includes(expected)),
    toEqual: (expected) => assert.notDeepStrictEqual(actual, expected),
  },
  toBe: (expected) => assert.strictEqual(actual, expected),
  toContain: (expected) => assert.ok(actual.includes(expected)),
  toEqual: (expected) => assert.deepStrictEqual(actual, expected),
});
