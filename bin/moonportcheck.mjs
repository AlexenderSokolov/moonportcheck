#!/usr/bin/env node
import metadata from '../package.json' with { type: 'json' };
import { HostError, parseArguments, readManifest, scan } from '../lib/host.mjs';

const help = `MoonPortCheck ${metadata.version} — portable-windows-v1

Usage:
  moonportcheck scan ROOT [--format text|json]
  moonportcheck check MANIFEST [--format text|json]
  moonportcheck --help
  moonportcheck --version

MANIFEST is a UTF-8 JSON array of {"path":"relative/name","kind":"file"|"directory"}.
scan includes hidden entries and never follows symbolic links or junctions.
Reports are written to stdout. Prefix paths beginning with '-' with './'.
Exit codes: 0 complete/pass; 1 findings; 2 invalid input; 3 incomplete scan or I/O error.`;

const options = parseArguments(process.argv.slice(2));
if (options.mode === 'help') {
  process.stdout.write(`${help}\n`);
} else if (options.mode === 'version') {
  process.stdout.write(`${metadata.version}\n`);
} else {
  let request;
  if (options.mode === 'error') {
    request = options;
  } else {
    try {
      if (options.mode === 'scan') {
        request = { mode: 'scan', format: options.format, ...await scan(options.target) };
      } else {
        request = { mode: 'check', format: options.format, manifest_text: await readManifest(options.target) };
      }
    } catch (error) {
      if (!(error instanceof HostError)) throw error;
      request = { mode: 'error', format: options.format, code: error.code, message: error.message, exit_code: error.exitCode };
    }
  }
  const { run_request } = await import('../dist/bridge.js');
  const response = JSON.parse(run_request(JSON.stringify(request)));
  process.stdout.write(`${response.output}\n`);
  // Preserve stdout when redirected or piped: do not terminate pending writes.
  process.exitCode = response.exit_code;
}
