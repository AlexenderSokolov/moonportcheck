#!/usr/bin/env node
import metadata from '../package.json' with { type: 'json' };
import { HostError, parseArguments, readConfig, readManifest, scan } from '../lib/host.mjs';

const help = `MoonPortCheck ${metadata.version} — portable-windows-v1

Usage:
  moonportcheck scan ROOT [--config FILE] [--exclude PATTERN]... [--baseline BASELINE.json] [--fail-on new] [--format text|json]
  moonportcheck snapshot ROOT [--config FILE] [--exclude PATTERN]...
  moonportcheck check MANIFEST [--config FILE] [--exclude PATTERN]... [--format text|json] [--report sarif]
  moonportcheck diff BEFORE.json AFTER.json [--format text|json|markdown]
  moonportcheck baseline create REPORT.json
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
diff compares two snapshot documents: exit 0 with no changes, 1 with changes,
2 for a malformed document or mismatched scopes, and 3 when either input is
incomplete. It never infers renames or content changes. --format markdown
renders a Markdown table.
check --report sarif emits a SARIF 2.1.0 document. Locations carry only the
artifact URI because the model has no source line numbers; no region or source
line is fabricated.
baseline create turns a complete schema 2 report into the baseline JSON
document (exit 0); non-schema-2 or incomplete reports exit 2. scan --baseline
compares the scan against that baseline and exits 2 when the baseline does not
match the profile, rules version, or effective scope; --fail-on new returns 1
only for fresh (new) or worsened groups, otherwise the whole problem set decides.
An incomplete scan still exits 3 and is never exempted by a baseline.
scan includes hidden entries and never follows symbolic links or junctions.
--config reads a versioned JSON configuration ({"schema_version":1,"exclude":[...]});
its exclusions and every --exclude are combined. No .gitignore is read implicitly.
Reports are written to stdout. Prefix paths beginning with '-' with './'.
Exit codes: 0 complete/pass; 1 findings/changes; 2 invalid input; 3 incomplete scan or I/O error.`;

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
          if (options.mode === 'scan' && options.baseline !== undefined) {
            request.baseline_text = await readManifest(options.baseline);
            if (options.fail_on) request.fail_on = true;
          }
        } else if (options.mode === 'diff') {
          const [before_text, after_text] = await Promise.all([
            readManifest(options.target),
            readManifest(options.after),
          ]);
          request = { mode: 'diff', format: options.format, before_text, after_text };
        } else if (options.mode === 'baseline') {
          request = { mode: 'baseline', format: 'json', report_text: await readManifest(options.target) };
        } else {
          request = { mode: 'check', format: options.format, manifest_text: await readManifest(options.target), exclude_patterns: scope.patterns };
          if (options.report) request.report = options.report;
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
