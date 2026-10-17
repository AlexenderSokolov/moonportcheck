import {createHash} from 'node:crypto';
export const interfaceHash=text=>createHash('sha256').update(text.replaceAll('\r\n','\n')).digest('hex');
export function verifyInterfaceBaseline(records,baseline){
  if(baseline?.schema_version!==1||!Array.isArray(baseline.files))throw new Error('Invalid local API baseline.');
  const expected=new Map(baseline.files.map(f=>[f.path,f.sha256]));
  if(expected.size!==baseline.files.length||expected.size!==records.length)throw new Error('Local API baseline file set changed.');
  for(const file of records)if(expected.get(file.path)!==interfaceHash(file.text))throw new Error(`Local API baseline mismatch: ${file.path}`);
}
