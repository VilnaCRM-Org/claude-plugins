// @ts-check
/** @type {import('@stryker-mutator/api/core').PartialStrykerOptions} */
export default {
  packageManager: 'bun',
  testRunner: 'jest',
  reporters: ['clear-text', 'progress'],
  coverageAnalysis: 'perTest',
  thresholds: { high: 100, break: 60 },
};
