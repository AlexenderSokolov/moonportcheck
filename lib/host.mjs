import fsPromises from 'node:fs/promises';
import path from 'node:path';

// ignoreBOM preserves a leading U+FEFF in a filename or manifest; decoding must
// never silently rename a path. JSON syntax policy belongs to the MoonBit core.
const utf8 = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
const compare = (left, right) => left < right ? -1 : left > right ? 1 : 0;

export class HostError extends Error {
  constructor(code, message, exitCode) {
    super(message);
    this.name = 'HostError';
    this.code = code;
    this.exitCode = exitCode;
  }
}

function errorSuffix(error) {
  // Native error.message contains absolute filenames. Only expose the bounded
  // errno token, which is useful for diagnosing EACCES/ENOENT without root leaks.
  return typeof error?.code === 'string' && /^[A-Z][A-Z0-9_]{0,39}$/.test(error.code)
    ? ` (${error.code})` : '';
}

export function parseArguments(args) {
  let format = 'text';
  // Preserve a valid output-format request even if another argument is invalid.
  for (let i = 0; i < args.length - 1; i++) {
    if (args[i] === '--format' && (args[i + 1] === 'text' || args[i + 1] === 'json')) format = args[i + 1];
  }
  const invalid = (message) => ({ mode: 'error', format, exit_code: 2, code: 'ARGUMENT_ERROR', message });
  if (args.length === 1 && args[0] === '--help') return { mode: 'help' };
  if (args.length === 1 && args[0] === '--version') return { mode: 'version' };
  const mode = args[0];
  if (!['check', 'scan', 'snapshot', 'diff', 'baseline', 'rules', 'explain'].includes(mode)) return invalid('Expected scan, snapshot, diff, baseline, check, rules or explain; use --help for usage.');
  let target;
  let after;
  let sawFormat = false;
  let sawConfig = false;
  let sawBaseline = false;
  let sawFailOn = false;
  let sawReport = false;
  let config = null;
  let baseline;
  let report;
  let failOn = false;
  const excludes = [];
  for (let i = 1; i < args.length; i++) {
    const argument = args[i];
    if (mode === 'baseline' && i === 1 && argument === 'create') continue;
    if (argument === '--format') {
      if (mode === 'snapshot' || mode === 'baseline') return invalid(`${mode} writes a fixed JSON document and does not accept --format.`);
      if (sawFormat) return invalid('--format may be supplied only once.');
      sawFormat = true;
      const value = args[++i];
      if (value === 'text' || value === 'json') {
        format = value;
      } else if ((mode === 'check' || mode === 'scan' || mode === 'diff') && value === 'markdown') {
        format = value;
      } else {
        return invalid('--format requires text or json, and markdown for check, scan and diff.');
      }
    } else if (argument === '--report') {
      if (mode !== 'check') return invalid('--report is only valid for check.');
      if (sawReport) return invalid('--report may be supplied only once.');
      sawReport = true;
      const value = args[++i];
      if (value !== 'sarif') return invalid('--report requires the value sarif.');
      report = 'sarif';
    } else if (argument === '--config') {
      if (mode === 'baseline') return invalid('baseline does not accept a config file.');
      if (sawConfig) return invalid('--config may be supplied only once.');
      sawConfig = true;
      const value = args[++i];
      if (value === undefined) return invalid('--config requires a file path.');
      config = value;
    } else if (argument === '--baseline') {
      if (mode !== 'scan') return invalid('--baseline is only valid for scan.');
      if (sawBaseline) return invalid('--baseline may be supplied only once.');
      sawBaseline = true;
      const value = args[++i];
      if (value === undefined) return invalid('--baseline requires a file path.');
      baseline = value;
    } else if (argument === '--fail-on') {
      if (mode !== 'scan') return invalid('--fail-on is only valid for scan.');
      if (sawFailOn) return invalid('--fail-on may be supplied only once.');
      sawFailOn = true;
      const value = args[++i];
      if (value !== 'new') return invalid('--fail-on requires the value new.');
      failOn = true;
    } else if (argument === '--exclude') {
      const value = args[++i];
      if (value === undefined) return invalid('--exclude requires a pattern.');
      excludes.push(value);
    } else if (argument.startsWith('-')) {
      return invalid('Unknown option; use --help for usage. Prefix option-like paths with ./ .');
    } else if (mode === 'diff' && target !== undefined && after === undefined) {
      after = argument;
    } else if (target !== undefined) {
      return invalid('Expected exactly one input path.');
    } else {
      target = argument;
    }
  }
  if (mode === 'rules') return config === null && excludes.length === 0 && target === undefined ? { mode, format } : invalid('rules does not accept an input path, config, or exclusions.');
  if (mode === 'explain' && (config !== null || excludes.length > 0)) return invalid('explain does not accept a config file or exclusions.');
  if (mode === 'diff' && (config !== null || excludes.length > 0)) return invalid('diff does not accept a config file or exclusions.');
  if (mode === 'baseline' && (config !== null || excludes.length > 0)) return invalid('baseline does not accept a config file or exclusions.');
  if (mode === 'scan' && sawBaseline === false && sawFailOn) return invalid('--fail-on requires --baseline.');
  if (mode !== 'check' && sawReport) return invalid('--report is only valid for check.');
  if (sawReport && format === 'markdown') return invalid('--report sarif conflicts with --format markdown.');
  if (!target) return invalid(mode === 'explain' ? 'A rule code is required.' : 'An input path is required.');
  if (mode === 'diff' && !after) return invalid('diff requires a before and an after snapshot path.');
  for (const value of [target, config, after, baseline].filter((item) => item !== null && item !== undefined)) {
    if (!value.isWellFormed() || value.includes('\0')) return invalid('Input and config paths must contain valid Unicode and no NUL character.');
  }
  for (const pattern of excludes) {
    if (!pattern.isWellFormed()) return invalid('Exclusion patterns must contain valid Unicode.');
  }
  if (mode === 'diff') return { mode, target, after, format, excludes, config };
  if (mode === 'check' && report === 'sarif') {
    return { mode, target, format, excludes, config, report };
  }
  if (mode === 'scan' && baseline !== undefined) {
    return { mode, target, format, excludes, config, baseline, ...(failOn ? { fail_on: true } : {}) };
  }
  return { mode, target, format, excludes, config };
}

export async function readManifest(filename, { fs = fsPromises } = {}) {
  let bytes;
  try {
    bytes = await fs.readFile(filename);
  } catch (error) {
    throw new HostError('INPUT_IO_ERROR', `Cannot read the manifest${errorSuffix(error)}.`, 3);
  }
  try {
    return utf8.decode(bytes);
  } catch {
    throw new HostError('INPUT_ENCODING', 'The manifest is not valid UTF-8.', 2);
  }
}

export async function readConfig(filename, { fs = fsPromises } = {}) {
  let bytes;
  try {
    bytes = await fs.readFile(filename);
  } catch (error) {
    throw new HostError('INPUT_IO_ERROR', `Cannot read the config file${errorSuffix(error)}.`, 3);
  }
  try {
    return utf8.decode(bytes);
  } catch {
    throw new HostError('INPUT_ENCODING', 'The config file is not valid UTF-8.', 2);
  }
}

function decodedName(raw) {
  const name = typeof raw === 'string' ? raw : utf8.decode(raw);
  if (!name.isWellFormed()) throw new Error('Unpaired surrogate');
  return name;
}

function invalidNameLabel(raw) {
  if (typeof raw !== 'string') return `<invalid-utf8:${Buffer.from(raw).toString('hex')}>`;
  const units = [];
  for (let i = 0; i < raw.length; i++) units.push(raw.charCodeAt(i).toString(16).padStart(4, '0'));
  return `<invalid-unicode:${units.join('')}>`;
}

/**
 * Enumerate metadata from a static, trusted delivery tree. Every discovered
 * child is lstat'ed; links/junctions are reported and not traversed. This is not
 * a defense against a concurrently modified or hostile filesystem (TOCTOU).
 * excludeMatch(path, kind) is an optional MoonBit-backed predicate; a directory
 * it excludes is still recorded as an entry but its subtree is not enumerated.
 */
export async function scan(root, { fs = fsPromises, excludeMatch = null } = {}) {
  const entries = [];
  const scan_issues = [];
  const issue = (code, relative, message) => scan_issues.push({ code, path: relative || '.', message });
  const absoluteRoot = path.resolve(root);
  const pending = [{ absolute: absoluteRoot, relative: '', isRoot: true }];
  while (pending.length > 0) {
    const current = pending.pop();
    let metadata;
    try {
      metadata = await fs.lstat(current.absolute);
    } catch (error) {
      issue('SCAN_IO_ERROR', current.relative, `Cannot read entry metadata${errorSuffix(error)}.`);
      continue;
    }
    if (metadata.isSymbolicLink()) {
      issue('SCAN_LINK_SKIPPED', current.relative, 'Symbolic link or junction was not followed.');
      continue;
    }
    if (!metadata.isFile() && !metadata.isDirectory()) {
      issue('SCAN_TYPE_UNSUPPORTED', current.relative, 'Entry type is neither a regular file nor a directory.');
      continue;
    }
    if (current.isRoot && !metadata.isDirectory()) {
      issue('SCAN_TYPE_UNSUPPORTED', '', 'The scan root must be a directory.');
      continue;
    }
    if (!current.isRoot) entries.push({ path: current.relative, kind: metadata.isDirectory() ? 'directory' : 'file' });
    if (!metadata.isDirectory()) continue;
    if (!current.isRoot && excludeMatch && await excludeMatch(current.relative, 'directory')) continue;
    let rawNames;
    try {
      rawNames = await fs.readdir(current.absolute, { encoding: 'buffer' });
    } catch (error) {
      issue('SCAN_IO_ERROR', current.relative, `Cannot enumerate directory${errorSuffix(error)}.`);
      continue;
    }
    for (const raw of rawNames) {
      let name;
      try {
        name = decodedName(raw);
      } catch {
        const label = invalidNameLabel(raw);
        issue('SCAN_NAME_ENCODING', current.relative ? `${current.relative}/${label}` : label, 'Filename cannot be represented losslessly as Unicode from UTF-8; entry was skipped.');
        continue;
      }
      pending.push({
        absolute: path.join(current.absolute, name),
        // Only the separator we insert is normalized. A POSIX backslash is
        // part of the filename and must reach the core as an invalid character.
        relative: current.relative ? `${current.relative}/${name}` : name,
        isRoot: false,
      });
    }
  }
  entries.sort((a, b) => compare(a.path, b.path) || compare(a.kind, b.kind));
  scan_issues.sort((a, b) => compare(a.code, b.code) || compare(a.path, b.path) || compare(a.message, b.message));
  return { entries, scan_issues };
}
