///|
/// A path entry describes a root-relative file or directory, never the scan root.
pub(all) enum EntryKind {
  File
  Directory
} derive(Eq, Debug)

///|
pub(all) struct PathEntry {
  path : String
  kind : EntryKind
} derive(Eq, Debug)

///|
pub(all) struct InputError {
  code : String
  message : String
} derive(Eq, Debug)

///|
pub(all) struct Diagnostic {
  code : String
  severity : String
  paths : Array[String]
  occurrences : Int
  message : String
} derive(Eq, Debug)

///|
pub(all) struct Summary {
  entries : Int
  files : Int
  directories : Int
  diagnostic_groups : Int
  scan_issues : Int
} derive(Eq, Debug)

///|
pub(all) struct Report {
  schema_version : Int
  profile : String
  source : String
  complete : Bool
  summary : Summary
  diagnostics : Array[Diagnostic]
  limitations : Array[String]
} derive(Eq, Debug)

///|
pub extend EntryKind with Eq::{equal, not_equal}

///|
pub extend EntryKind with @debug.Debug::{to_repr}

///|
pub extend PathEntry with Eq::{equal, not_equal}

///|
pub extend PathEntry with @debug.Debug::{to_repr}

///|
pub extend InputError with Eq::{equal, not_equal}

///|
pub extend InputError with @debug.Debug::{to_repr}

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub extend Summary with Eq::{equal, not_equal}

///|
pub extend Summary with @debug.Debug::{to_repr}

///|
pub extend Report with Eq::{equal, not_equal}

///|
pub extend Report with @debug.Debug::{to_repr}
