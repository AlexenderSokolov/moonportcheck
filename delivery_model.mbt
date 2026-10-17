///|
pub(all) struct DeliveryOrigin {
  root : String
  path : String
} derive(Eq, Debug)

///|
pub(all) struct DeliveryTree {
  id : String
  snapshot : Snapshot
} derive(Eq, Debug)

///|
pub(all) struct DeliveryMapping {
  mode : String
  source : String
  from : String
  to : String
} derive(Eq, Debug)

///|
pub(all) struct DeliverySpec {
  sources : Array[DeliveryTree]
  target : DeliveryTree
  mappings : Array[DeliveryMapping]
} derive(Eq, Debug)

///|
pub(all) struct DeliveryOperation {
  kind : String
  source : String
  from : String
  to : String
  origin : DeliveryOrigin
} derive(Eq, Debug)

///|
pub(all) struct DeliveryDiagnostic {
  code : String
  path : String
  message : String
  step : Int
} derive(Eq, Debug)

///|
pub(all) struct DeliveryPlan {
  status : String
  basis : String
  operations : Array[DeliveryOperation]
  temporary_paths : Array[String]
  diagnostics : Array[DeliveryDiagnostic]
} derive(Eq, Debug)

///|
pub(all) struct DeliveryStateEntry {
  path : String
  kind : EntryKind
  origin : DeliveryOrigin
} derive(Eq, Debug)

///|
pub(all) struct DeliveryTrace {
  step : Int
  kind : String
  from : String
  to : String
  origin : DeliveryOrigin
} derive(Eq, Debug)

///|
pub(all) struct DeliveryAudit {
  status : String
  valid : Bool
  first_failed_step : Int
  diagnostics : Array[DeliveryDiagnostic]
  final_entries : Array[DeliveryStateEntry]
  trace : Array[DeliveryTrace]
} derive(Eq, Debug)

///|
struct DeliveryIntent {
  mode : String
  source : String
  from : String
  to : String
  origin : DeliveryOrigin
} derive(Eq, Debug)

///|
pub extend DeliveryOrigin with Eq::{equal, not_equal}

///|
pub extend DeliveryOrigin with @debug.Debug::{to_repr}

///|
pub extend DeliveryTree with Eq::{equal, not_equal}

///|
pub extend DeliveryTree with @debug.Debug::{to_repr}

///|
pub extend DeliveryMapping with Eq::{equal, not_equal}

///|
pub extend DeliveryMapping with @debug.Debug::{to_repr}

///|
pub extend DeliverySpec with Eq::{equal, not_equal}

///|
pub extend DeliverySpec with @debug.Debug::{to_repr}

///|
pub extend DeliveryOperation with Eq::{equal, not_equal}

///|
pub extend DeliveryOperation with @debug.Debug::{to_repr}

///|
pub extend DeliveryDiagnostic with Eq::{equal, not_equal}

///|
pub extend DeliveryDiagnostic with @debug.Debug::{to_repr}

///|
pub extend DeliveryPlan with Eq::{equal, not_equal}

///|
pub extend DeliveryPlan with @debug.Debug::{to_repr}

///|
pub extend DeliveryStateEntry with Eq::{equal, not_equal}

///|
pub extend DeliveryStateEntry with @debug.Debug::{to_repr}

///|
pub extend DeliveryTrace with Eq::{equal, not_equal}

///|
pub extend DeliveryTrace with @debug.Debug::{to_repr}

///|
pub extend DeliveryAudit with Eq::{equal, not_equal}

///|
pub extend DeliveryAudit with @debug.Debug::{to_repr}

///|
pub extend DeliveryIntent with Eq::{equal, not_equal}

///|
pub extend DeliveryIntent with @debug.Debug::{to_repr}
