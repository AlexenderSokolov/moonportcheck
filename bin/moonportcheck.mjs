#!/usr/bin/env node
import metadata from '../package.json' with { type: 'json' };
import { HostError, parseArguments, readConfig, readManifest, scan } from '../lib/host.mjs';

const help = `MoonPortCheck ${metadata.version} — portable-windows-v1

Usage:
  moonportcheck scan ROOT [--config FILE] [--exclude PATTERN]... [--format text|json]
  moonportcheck snapshot ROOT [--config FILE] [--exclude PATTERN]...
  moonportcheck check MANIFEST [--config FILE] [--exclude PATTERN]... [--format text|json]
  moonportcheck rules [--format text|json]
  moonportcheck explain CODE [--format text|json]
  moonportcheck --help
  moonportcheck --version

MANIFEST is a UTF-8 JSON array of {"path":"relative/name","kind":"file"|"directory"}
or a snapshot document written by this command. check on a snapshot inherits its
scope; extra exclusions can only shrink it and an incomplete snapshot stays
incomplete.
snapshot writes the fixed-format snapshot JSON document to stdout (no --format);
exit 0 when the scan was complete and 3 when it was not.
scan includes hidden entries and never follows symbolic links or junctions.
--config reads a versioned JSON configuration ({"schema_version":1,"exclude":[...]});
its exclusions and every --exclude are combined. No .gitignore is read implicitly.
Reports are written to stdout. Prefix paths beginning with '-' with './'.
Exit codes: 0 complete/pass; 1 findings; 2 invalid input; 3 incomplete scan or I/O error.`;

async function resolveScope(runRequest, options) {
  if (options.config === null && options.excludes.length === 0) return { patterns: [] };
  const request = { mode: 'scope', format: options.format, cli_exclude: options.excludes };
  if (options.config !== null) request.config_text = await readConfig(options.config);
  const response = JSON.parse(runRequest(JSON.stringify(request)));
  if (response.exit_code !== 0) return { error: response };
  return { patterns: JSON.parse(response.output).patterns };
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  if (options.mode === 'help') {
    process.stdout.write(`${help}\n`);
    return;
  }
  if (options.mode === 'version') {
    process.stdout.write(`${metadata.version}\n`);
    return;
  }
  const { run_request } = await import('../dist/bridge.js');
  let request;
  if (options.mode === 'error') {
    request = options;
  } else {
    try {
      if (options.mode === 'rules' || options.mode === 'explain') {
        request = { mode: options.mode, format: options.format, code: options.target };
      } else {
        const scope = await resolveScope(run_request, options);
        if (scope.error) {
          process.stdout.write(`${scope.error.output}\n`);
          process.exitCode = scope.error.exit_code;
          return;
        }
        if (options.mode === 'scan' || options.mode === 'snapshot') {
          // Node adapts the filesystem; every pruning decision comes from the
          // MoonBit matcher so there is no second glob implementation here.
          const prune = scope.patterns.length === 0 ? null : (relative, kind) => {
            const response = JSON.parse(run_request(JSON.stringify({ mode: 'excluded', format: 'json', patterns: scope.patterns, path: relative, kind })));
            return response.exit_code === 0 && response.output === 'true';
          };
          const scanned = await scan(options.target, { excludeMatch: prune });
          request = options.mode === 'snapshot'
            ? { mode: 'snapshot', format: 'json', ...scanned, exclude_patterns: scope.patterns }
            : { mode: 'scan', format: options.format, ...scanned, exclude_patterns: scope.patterns };
        } else {
          request = { mode: 'check', format: options.format, manifest_text: await readManifest(options.target), exclude_patterns: scope.patterns };
        }
      }
    } catch (error) {
      if (!(error instanceof HostError)) throw error;
      request = { mode: 'error', format: options.format, code: error.code, message: error.message, exit_code: error.exitCode };
    }
  }
  const response = JSON.parse(run_request(JSON.stringify(request)));
  process.stdout.write(`${response.output}\n`);
  // Preserve stdout when redirected or piped: do not terminate pending writes.
  process.exitCode = response.exit_code;
}

await main();
