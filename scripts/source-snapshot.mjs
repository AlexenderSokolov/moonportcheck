// One inventory for acceptance evidence, candidate identity and source export.
// Build/cache/output directories are excluded; untracked source files are kept.
import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';

const excluded = new Set(['.git', '.toolchains', '_build', 'target', 'artifacts', 'dist', 'node_modules']);
export async function collectSourceSnapshot(root) {
  const files = [];
  async function inventory(directory, relative = '') {
    for (const entry of (await fs.readdir(directory, { withFileTypes: true })).sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0)) {
      if (excluded.has(entry.name)) continue;
      const next = relative ? `${relative}/${entry.name}` : entry.name;
      if (entry.isDirectory()) await inventory(path.join(directory, entry.name), next);
      else if (entry.isFile()) {
        const bytes = await fs.readFile(path.join(directory, entry.name));
        files.push({ path: next, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') });
      } else {
        throw new Error(`Source snapshot cannot silently omit a nonregular entry: ${next}`);
      }
    }
  }
  await inventory(root);
  const text = JSON.stringify(files, null, 2) + '\n';
  return { format: 'moonportcheck-source-snapshot', version: 1, files, sha256: createHash('sha256').update(text).digest('hex') };
}

export function candidateSourceIdentity(metadata, snapshot) {
  return metadata.source_state === 'committed_clean'
    ? metadata.tested_sha.slice(0, 7) : `worktree-${snapshot.sha256.slice(0, 12)}`;
}

export function verifyCandidateSource(provenance,metadata,snapshot) {
  for(const field of ['source_commit','source_state','tested_sha'])assert.equal(provenance[field],metadata[field],`Candidate source identity differs: ${field}`);
  assert.equal(provenance.source_snapshot_sha256,snapshot.sha256,'Candidate source snapshot differs from current source');
}
