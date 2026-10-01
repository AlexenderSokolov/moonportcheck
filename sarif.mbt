///|
/// Product version embedded in the SARIF driver metadata. Keep in step with
/// package.json; the release script checks the match.
const PRODUCT_VERSION : String = "0.2.0"

///|
/// The URI code space for artifact locations: ASCII letters, digits and
/// - . _ ~ stay literal; / is a separator; everything else is percent-encoded
/// from its UTF-8 bytes. This is deliberately conservative (queries and
/// fragments are encoded) so the URI is safe in any SARIF consumer.
fn uri_unreserved(code : Int) -> Bool {
  (code >= 48 && code <= 57) ||
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122) ||
  code == 45 ||
  code == 46 ||
  code == 95 ||
  code == 126 ||
  code == 47
}

///|
/// The hex digit Char for a 4-bit nibble. This toolchain's String indexing
/// returns a UTF-16 code unit, so the digit is converted explicitly.
fn hex_char(value : Int) -> Char {
  HEX_DIGITS[value].to_int().unsafe_to_char()
}

///|
const HEX_DIGITS : String = "0123456789ABCDEF"

///|
/// Append the percent-encoded UTF-8 form of one byte to the char buffer.
fn push_pct(chars : Array[Char], byte : Int) -> Unit {
  chars.push('%')
  chars.push(hex_char(byte >> 4))
  chars.push(hex_char(byte & 0xF))
}

///|
/// Percent-encode a relative path as a URI reference, preserving / separators.
pub fn uri_escape_path(value : String) -> String {
  let chars : Array[Char] = []
  for char in value {
    let code = char.to_int()
    if code >= 0xD800 && code <= 0xDFFF {
      // Lone surrogates are not valid UTF-8; substitute the replacement glyph.
      push_pct(chars, 0xEF)
      push_pct(chars, 0xBF)
      push_pct(chars, 0xBD)
    } else if uri_unreserved(code) {
      chars.push(char)
    } else if code <= 0x7F {
      push_pct(chars, code)
    } else if code <= 0x7FF {
      push_pct(chars, 0xC0 | (code >> 6))
      push_pct(chars, 0x80 | (code & 0x3F))
    } else if code <= 0xFFFF {
      push_pct(chars, 0xE0 | (code >> 12))
      push_pct(chars, 0x80 | ((code >> 6) & 0x3F))
      push_pct(chars, 0x80 | (code & 0x3F))
    } else {
      push_pct(chars, 0xF0 | (code >> 18))
      push_pct(chars, 0x80 | ((code >> 12) & 0x3F))
      push_pct(chars, 0x80 | ((code >> 6) & 0x3F))
      push_pct(chars, 0x80 | (code & 0x3F))
    }
  }
  String::from_iter(chars.iter())
}

///|
/// SARIF 2.1.0 level for a diagnostic severity: error/warning pass through and
/// anything else (including the scanning phase) becomes a note.
fn sarif_level(severity : String) -> String {
  if severity == "error" {
    "error"
  } else if severity == "warning" {
    "warning"
  } else {
    "note"
  }
}

///|
/// SARIF result for one report group. Locations carry only the artifact URI;
/// the model has no source line numbers, so no region is ever fabricated.
fn sarif_result(
  code : String,
  level : String,
  message : String,
  uri_path : String,
  members : Array[SourceMember],
) -> String {
  let locations = if check_path(uri_path, 1, []) is Some(_) {
    ",\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":" +
    quote(uri_escape_path(uri_path)) +
    "}}}]"
  } else {
    ""
  }
  let navigable = members.filter(item => check_path(item.path, 1, []) is Some(_))
  let related = if navigable.is_empty() {
    ""
  } else {
    ",\"relatedLocations\":[" +
    navigable
    .map(item => {
      "{\"physicalLocation\":{\"artifactLocation\":{\"uri\":" +
      quote(uri_escape_path(item.path)) +
      "}}}"
    })
    .join(",") +
    "]"
  }
  "{\"ruleId\":" +
  quote(code) +
  ",\"level\":" +
  quote(level) +
  ",\"message\":{\"text\":" +
  quote(message) +
  "}" +
  locations +
  related +
  ",\"properties\":{\"path\":" +
  quote(uri_path) +
  ",\"members\":" +
  render_source_members(members) +
  "}" +
  "}"
}

///|
fn sarif_results(report : DetailedReport) -> String {
  let parts : Array[String] = []
  for diagnostic in report.diagnostics {
    parts.push(
      sarif_result(
        diagnostic.code,
        sarif_level(diagnostic.severity),
        diagnostic.message,
        diagnostic.anchor,
        diagnostic.members,
      ),
    )
  }
  for issue in report.scan_issues {
    parts.push(
      sarif_result(
        issue.code,
        "note",
        issue.message,
        if issue.path.is_empty() {
          "."
        } else {
          issue.path
        },
        [],
      ),
    )
  }
  parts.join(",")
}

///|
fn sarif_rule_descriptors() -> String {
  rules()
  .map(rule => {
    "{\"id\":" +
    quote(rule.code) +
    ",\"name\":" +
    quote(rule.title) +
    ",\"shortDescription\":{\"text\":" +
    quote(rule.title) +
    "},\"fullDescription\":{\"text\":" +
    quote(rule.reason) +
    "},\"help\":{\"text\":" +
    quote(rule.suggestion) +
    "},\"defaultConfiguration\":{\"level\":\"error\"}}"
  })
  .join(",")
}

///|
fn sarif_invocation(report : DetailedReport) -> String {
  let notifications = report.limitations.map(limitation => {
    "{\"descriptor\":{\"id\":\"MOONPORT_RUN_LIMIT\"},\"message\":{\"text\":" +
    quote(limitation) +
    "}}"
  })
  let notification_json = if notifications.is_empty() {
    ""
  } else {
    ",\"toolExecutionNotifications\":[" + notifications.join(",") + "]"
  }
  "{\"executionSuccessful\":" +
  report.complete.to_json().stringify() +
  notification_json +
  "}"
}

///|
/// A complete SARIF 2.1.0 document for a schema 2 report. The document never
/// encodes timestamps, absolute paths or source line numbers.
pub fn render_check_sarif(report : DetailedReport) -> String {
  "{\"version\":\"2.1.0\",\"$schema\":\"https://json.schemastore.org/sarif-2.1.0.json\",\"runs\":[" +
  "{\"tool\":{\"driver\":{" +
  "\"name\":\"MoonPortCheck\"," +
  "\"informationUri\":\"https://github.com/AlexenderSokolov/moonportcheck\"," +
  "\"version\":\"" +
  PRODUCT_VERSION +
  "\",\"rules\":[" +
  sarif_rule_descriptors() +
  "]}},\"invocations\":[" +
  sarif_invocation(report) +
  "],\"results\":[" +
  sarif_results(report) +
  "]}]}"
}
