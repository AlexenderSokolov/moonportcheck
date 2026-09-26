///|
/// Human-readable guidance for an existing audit rule or scan issue.
pub(all) struct RuleInfo {
  code : String
  title : String
  reason : String
  examples : Array[String]
  suggestion : String
} derive(Eq, Debug)

///|
pub extend RuleInfo with Eq::{equal, not_equal}

///|
pub extend RuleInfo with @debug.Debug::{to_repr}

///|
/// Return all portable-windows-v1 rules and scan issues in ordinal code order.
/// Each call owns its arrays; editing the returned examples does not change the catalog.
pub fn rules() -> Array[RuleInfo] {
  [
    {
      code: "NAME_INVALID_CHAR",
      title: "Name contains a forbidden character",
      reason: "Windows name components cannot contain < > : \" \\ | ? * or U+0000 through U+001F. In this profile, / separates components; a backslash remains an invalid name character.",
      examples: ["notes/a:b.txt", "bad\\name", "bad\nname"],
      suggestion: "Rename the affected component using permitted characters and update references to it. Do not silently turn a literal backslash into a directory separator.",
    },
    {
      code: "NAME_RESERVED",
      title: "Name uses a Windows device name",
      reason: "The stem before the first period matches CON, PRN, AUX, NUL, COM1 through COM9, or LPT1 through LPT9 without regard to ASCII case. COM and LPT also reserve superscript 1, 2 and 3; adding an extension does not make these names portable.",
      examples: ["CON.txt", "assets/nul.tar.gz", "logs/LPT².log"],
      suggestion: "Choose a non-device stem, for example console-output.txt instead of CON.txt. Changing only the extension is insufficient.",
    },
    {
      code: "NAME_TRAILING_DOT_SPACE",
      title: "Name ends in a period or space",
      reason: "A component ends in an ASCII period or space, which normal Windows shell and file operations do not preserve reliably. This applies to intermediate directories as well as the final name.",
      examples: ["report.txt.", "data /results.csv"],
      suggestion: "Rename the affected component without the trailing period or space, update references, and check that the new name does not collide with another entry.",
    },
    {
      code: "PATH_ABSOLUTE",
      title: "Path is absolute or UNC-style",
      reason: "A leading / or backslash denotes a rooted path. Manifests describe paths relative to the delivery root, so absolute and UNC paths cannot identify portable entries within that root.",
      examples: ["/data/result.csv", "\\\\server\\share\\result.csv"],
      suggestion: "Choose the intended delivery root and supply each entry's relative path with / separators. Confirm the entry belongs to that root before converting it.",
    },
    {
      code: "PATH_CASE_COLLISION",
      title: "Different spellings collide under ASCII case folding",
      reason: "Two distinct path-prefix spellings become equal when A through Z are folded to a through z. Intermediate directories participate even when their contained files have different names. Unicode case equivalence is outside this profile.",
      examples: ["Data/a.csv", "data/b.csv"],
      suggestion: "Use one consistent spelling for each intended directory. If entries are meant to remain distinct, rename them so they also differ after ASCII case folding, then update references.",
    },
    {
      code: "PATH_DOT_COMPONENT",
      title: "Path contains a dot or parent component",
      reason: "A component is exactly '.' or '..'. This profile rejects these traversal components rather than normalizing them or guessing the intended relative entry.",
      examples: ["./report.txt", "data/../report.txt"],
      suggestion: "Resolve the intended entry against the chosen delivery root and write its direct relative path. Confirm it stays inside the root; do not blindly strip parent components.",
    },
    {
      code: "PATH_DRIVE",
      title: "Path has a Windows drive prefix",
      reason: "An initial ASCII letter followed by a colon is drive-qualified, including drive-relative forms such as C:report.txt. Such a path depends on a Windows drive context instead of the delivery root.",
      examples: ["C:report.txt", "D:/data/report.txt"],
      suggestion: "Locate the file relative to the intended delivery root and record that relative path with / separators. Do not merely remove the drive prefix without checking the location.",
    },
    {
      code: "PATH_DUPLICATE",
      title: "The same exact path occurs more than once",
      reason: "Multiple supplied entries have the same exact path string. A single grouped finding preserves the input occurrence count, including entries with different declared kinds.",
      examples: ["results.csv", "results.csv"],
      suggestion: "Reconcile the repeated entries and keep one intended entry per exact path. If their kinds differ, also resolve the file/directory conflict before rebuilding the manifest.",
    },
    {
      code: "PATH_EMPTY",
      title: "Path is empty",
      reason: "An empty string does not identify a file or directory relative to the delivery root. The scan root itself is not an entry.",
      examples: [""],
      suggestion: "Provide the intended nonempty relative path, or omit an entry that was only meant to describe the delivery root.",
    },
    {
      code: "PATH_EMPTY_COMPONENT",
      title: "Path contains an empty component",
      reason: "A nonempty path has a leading, repeated, or trailing /, leaving an empty component. Directory entries use their relative name without a trailing slash.",
      examples: ["data//results.csv", "data/"],
      suggestion: "Write the intended relative path with exactly one / between components and no trailing slash. Declare directories with kind directory instead of adding /.",
    },
    {
      code: "PATH_KIND_CONFLICT",
      title: "A path denotes both a file and a directory",
      reason: "After ASCII case folding, a prefix is used both as a file and as a directory. A parent prefix needed by a descendant is an implicit directory even if no directory entry was supplied.",
      examples: ["artifact", "artifact/report.txt"],
      suggestion: "Decide whether the conflicting location is a file or a directory. Correct an inaccurate kind, or rename the file or directory and update its descendants and references.",
    },
    {
      code: "SCAN_IO_ERROR",
      title: "Filesystem metadata could not be read",
      reason: "Reading the scan root, enumerating a directory, or inspecting an entry failed. Previously discovered entries can still be checked, but the scan is incomplete and exits 3.",
      examples: [
        "locked/ (directory enumeration denied)", "missing.txt (entry disappeared before metadata inspection)",
      ],
      suggestion: "Check that the root exists and metadata access is permitted. Resolve the reported read failure and rerun against a stable tree before treating the scan as complete.",
    },
    {
      code: "SCAN_LINK_SKIPPED",
      title: "A symbolic link or junction was skipped",
      reason: "The scanner does not follow symbolic links or Windows junctions, including a linked scan root. Their targets are not covered, so the scan is incomplete and exits 3.",
      examples: [
        "linked-data -> ../external-data", ". (scan root is a junction)",
      ],
      suggestion: "Decide what should actually be delivered. Materialize the intended contents as ordinary files and directories in the delivery tree, or audit a deliberately selected target separately; rerun the delivery scan after resolving the link.",
    },
    {
      code: "SCAN_NAME_ENCODING",
      title: "A filename cannot be represented losslessly",
      reason: "The scanner found filename bytes that are not valid UTF-8 or a name with an unpaired UTF-16 surrogate. It does not replace invalid data or guess a spelling; the scan is incomplete and exits 3.",
      examples: [
        "name containing raw byte 0xFF", "name containing an unpaired UTF-16 surrogate",
      ],
      suggestion: "Use filesystem tools that preserve the original name to identify and rename the entry to valid Unicode. Verify the replacement refers to the intended entry, then rerun the scan.",
    },
    {
      code: "SCAN_TYPE_UNSUPPORTED",
      title: "The scan encountered an unsupported entry type",
      reason: "The scan root must be a directory, and scanned children must be regular files or directories. Other entry types are not covered, so the scan is incomplete and exits 3; links have their own scan issue.",
      examples: [
        "events.pipe (named pipe)", "service.sock (Unix-domain socket)", "report.txt (regular file supplied as the scan root)",
      ],
      suggestion: "Supply a directory as the scan root. Prepare a delivery tree of ordinary files and directories, replacing unsupported runtime objects with the intended portable data, then rerun the scan.",
    },
  ]
}

///|
/// Look up an exact, case-sensitive diagnostic code.
pub fn explain(code : String) -> RuleInfo? {
  for rule in rules() {
    if rule.code == code {
      return Some(rule)
    }
  }
  None
}

///|
/// Serialize a catalog or selected rules as an array, sorted by diagnostic code.
pub fn render_rules_json(items : Array[RuleInfo]) -> String {
  let sorted = items.copy()
  sorted.sort_by((a, b) => ordinal_compare(a.code, b.code))
  let rendered = sorted.map(rule => {
    "{\"code\":" +
    quote(rule.code) +
    ",\"title\":" +
    quote(rule.title) +
    ",\"reason\":" +
    quote(rule.reason) +
    ",\"examples\":" +
    json_strings(rule.examples) +
    ",\"suggestion\":" +
    quote(rule.suggestion) +
    "}"
  })
  "[" + rendered.join(",") + "]"
}

///|
/// Render guidance in code order. Example paths are quoted so controls remain data.
pub fn render_rules_text(items : Array[RuleInfo]) -> String {
  let sorted = items.copy()
  sorted.sort_by((a, b) => ordinal_compare(a.code, b.code))
  let blocks = sorted.map(rule => {
    "[" +
    rule.code +
    "] " +
    rule.title +
    "\n" +
    "Reason: " +
    rule.reason +
    "\n" +
    "Examples: " +
    rule.examples.map(quote).join(", ") +
    "\n" +
    "Suggestion: " +
    rule.suggestion
  })
  blocks.join("\n\n")
}
