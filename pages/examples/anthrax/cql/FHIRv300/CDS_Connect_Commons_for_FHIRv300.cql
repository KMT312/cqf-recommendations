// CDS Connect Commons for FHIRv300
// Change log:
// - 1.3.1:
//   - Changed C.dateRecorded to C.dateRecorded.value in ConditionLookBack
//   - Changed G.statusDate to G.statusDate.value in GoalLookBack
// - 1.3.2:
//   - Added NotCancelled() and EncounterLookback() functions.
library CDS_Connect_Commons_for_FHIRv300 version '1.3.2'

using FHIR version '3.0.0'

// Include the FHIRHelpers library for simplifying interacton w/ the FHIR data model
include FHIRHelpers version '3.0.0' called FHIRHelpers

// -------------------------------------------------- GENERAL ---------------------------------------------------------

/**
 * A null-safe version of ToConcept.  Whereas FHIRHelpers.ToConcept will take a null argument and produce a
 * System.Concept that is empty, this implementation returns null instead.
 * @param C - a FHIR CodeableConcept
 * @returns {System.Concept} a CQL Concept or null if null was passed in
 */
define function NullSafeToConcept(Cpt FHIR.CodeableConcept):
  if Cpt is not null then FHIRHelpers.ToConcept(Cpt) else null

/**
 * A null-safe version of ToInterval for Period.  Whereas FHIRHelpers.ToInterval will take a null argument and produce a
 * System.Interval that is empty, this implementation returns null instead.
 * @param P - a FHIR Period
 * @returns {System.Interval} a CQL Interval or null if null was passed in
 */
define function NullSafePeriodToInterval(Pd FHIR.Period):
  if Pd is not null then Interval[Pd."start".value, Pd."end".value] else null

/**
 * A null-safe version of ToInterval for Range.  Whereas FHIRHelpers.ToInterval will take a null argument and produce a
 * System.Interval that is empty, this implementation returns null instead.
 * @param P - a FHIR Range
 * @returns {System.Interval} a CQL Interval or null if null was passed in
 */
define function NullSafeRangeToInterval(Rg FHIR.Range):
  if Rg is not null
    then Interval[NullSafeToQuantity(Rg.low), NullSafeToQuantity(Rg.high)]
  else null

/**
 * Same as NullSafePeriodToInterval; kept for backward compatibility.  [Deprecated]
 * @param P - a FHIR Period
 * @returns {System.Interval} a CQL Interval or null if null was passed in
 */
define function NullSafeToInterval(Pd FHIR.Period):
  NullSafePeriodToInterval(Pd)

/**
 * A null-safe version of ToQuantity.  Whereas FHIRHelpers.ToQuantity will take a null argument and produce a
 * System.Quantity that is empty, this implementation returns null instead.
 * @param C - a FHIR Quantity
 * @returns {System.Quantity} a CQL Quantity or null if null was passed in
 */
define function NullSafeToQuantity(Qty FHIR.Quantity):
  if Qty is not null then
    System.Quantity {
      value: Qty.value.value,
      unit: Coalesce(Qty.unit.value, Qty.code.value)
    }
  else null

// -------------------------------------------------- OBSERVATIONS -----------------------------------------------------

/**
 * Filters Observations by a concept rather than by a ValueSet.  In CQL 1.3, this will be built into the retrieve,
 * but for now, we must use a query where clause.
 * @param Koncept - the concept to filter on (intentionally mispelled to avoid naming clashes)
 * @returns {List<Observation>} a list of Observations matching the concept, or null if null was passed in
 */
define function ObservationsByConcept(Koncept System.Concept):
  [Observation] O where NullSafeToConcept(O.code) ~ Koncept

/**
 * Observations that are complete and verified. In FHIR STU3, there are two statuses that indicate this state: 'final'
 * and 'amended'.
 * @see https://www.hl7.org/fhir/STU3/valueset-observation-status.html
 * @param ObsList - a list of Observations
 * @returns {List<Observation>} a list of verified Observations, or null if null was passed in
 */
define function Verified(ObsList List<Observation>):
  ObsList O where O.status.value in {'final', 'amended'}

/**
 * Observations that have quantity values recorded in the requested unit.
 * @param ObsList - a list of Observations
 * @param Unit - the unit to require in the Observations quantity value
 * @returns {List<Observation>} a list of Observations with the required unit, or null if null was passed in
 */
define function WithUnit(ObsList List<Observation>, Unit String):
  ObsList O where O.value.unit.value = Unit or O.value.code.value = Unit

/**
 * Observations with an effective or issued date in the specified "look back" period.  For example, LDL-C Tests in the
 * last 6 years.
 * TODO: Rename to LookBack once the execution engine supports overloaded functions.
 * @param ObsList - a list of Observations
 * @returns {List<Observation>} a list of Observations with effective or issued date specified lookback period, or null
 * if null was passed in
 */
define function ObservationLookBack(ObsList List<Observation>, LookBack System.Quantity):
  ObsList O
    let LookBackInterval: Interval[Now() - LookBack, Now()]
    where O.effective.value in LookBackInterval
      or NullSafeToInterval(O.effective) overlaps LookBackInterval
      or O.issued.value in LookBackInterval

/**
 * The most recent observation.  For each Observation, this algorithm will use the FindDate function, which uses the
 * first non-null date value from these fields: effectiveDateTime, effectivePeriod.end, effectivePeriod.start, issued.
 * The found date will be used to compare Observations and determine the most recent one.
 * @see FindDate(Observation)
 * @param ObsList - a list of Observations
 * @returns {Observation} the most recent Observation from the list, or null if null was passed in
 */
define function MostRecent(ObsList List<Observation>):
  Last(ObsList O sort by Coalesce(effective.value, effective."end".value, effective."start".value, issued.value))

/**
 * Extracts the quantity value from an Observation, returning it as a CQL Quantity
 * @param Obs - an observation
 * @returns {System.Quantity} the Observation's value as a quantity, or null if there is no quantity value
 */
define function QuantityValue(Obs Observation):
  NullSafeToQuantity(Obs.value)

/**
 * Extracts the CodeableConcept value from an Observation, returning it as a CQL Concept
 * @param Obs - an observation
 * @returns {System.Concept} the Observation's value as a concept, or null if there is no CodeabeConcept value
 */
define function ConceptValue(Obs Observation):
  NullSafeToConcept(Obs.value)

/**
 * Finds the first non-null meaningful date that can be associated with this Observation.  This will look through the
 * following fields in the following order: effectiveDateTime, effectivePeriod.end, effectivePeriod.start, issued.
 * @param Obs - an Observation
 * @returns {System.DateTime} the first non-null meaningful date, or null if non is found
 */
define function FindDate(Obs Observation):
  Coalesce(Obs.effective.value, Obs.effective."end".value, Obs.effective."start".value, Obs.issued.value)

// TODO: Confirm that this works as expected
/**
 * The highest observation.
 * The value will be used to compare Observations and determine the highest one.
 * @param ObsList - a list of Observations
 * @returns {System.Quantity} the quantity with the highest value from the list, or null if null was passed in
 */
define function HighestObservation(ObsList List<Observation>):
  Max(ObsList O return NullSafeToQuantity(O.value))


// -------------------------------------------------- CONDITIONS -------------------------------------------------------

/**
 * Filters Conditions by a concept rather than by a ValueSet.  In CQL 1.3, this will be built into the retrieve,
 * but for now, we must use a query where clause.
 * @param Koncept - the concept to filter on (intentionally mispelled to avoid naming clashes)
 * @returns {List<Observation>} a list of Conditions matching the concept, or null if null was passed in
 */
define function ConditionsByConcept(Koncept System.Concept):
  [Condition] C where NullSafeToConcept(C.code) ~ Koncept

/**
 * Conditions that are confirmed. In FHIR STU3, this is reflected by verificationStatus: 'confirmed'.
 * @see https://www.hl7.org/fhir/STU3/valueset-condition-ver-status.html
 * @param CondList - a list of Conditions
 * @returns {List<Condition>} a list of confirmed Conditions, or null if null was passed in
 */
define function Confirmed(CondList List<Condition>):
  CondList C where C.verificationStatus.value = 'confirmed'

/**
 * Conditions that are active. In FHIR STU3, this is reflected by clinicalStatus: 'active' and the absence of any
 * abatement information (i.e., if it abated, it is no longer active).
 * TODO: Rename to Active once the execution engine supports overloaded functions.
 * @see https://www.hl7.org/fhir/STU3/valueset-condition-clinical.html
 * @param CondList - a list of Conditions
 * @returns {List<Condition>} a list of active Conditions, or null if null was passed in
 */
define function ActiveCondition(CondList List<Condition>):
  CondList C
    where C.clinicalStatus.value = 'active'
      and C.abatement is null

/**
 * Conditions that are active or recurring. In FHIR STU3, this is reflected by clinicalStatus: 'active' or 'recurrence'.
 * We do not check for null abatement information because it may have dates from when the now recurring condition
 * initially went into remission.
 * @see https://www.hl7.org/fhir/STU3/valueset-condition-clinical.html
 * @param CondList - a list of Conditions
 * @returns {List<Condition>} a list of active or recurring Conditions, or null if null was passed in
 */
define function ActiveOrRecurring(CondList List<Condition>):
  CondList C where C.clinicalStatus.value in {'active', 'recurrence'}

/**
 * Conditions with an onset or recorded date in the specified "look back" period.  For example, pregnancy in
 * the last 42 weeks.
 * TODO: Rename to LookBack once the execution engine supports overloaded functions.
 * @param CondList - a list of Conditions
 * @returns {List<Condition>} a list of Conditions with onset or recorded date specified lookback period, or null
 * if null was passed in
 */
define function ConditionLookBack(CondList List<Condition>, LookBack System.Quantity):
  CondList C
    let LookBackInterval: Interval[Now() - LookBack, Now()]
    where C.onset.value in LookBackInterval
      or NullSafeToInterval(C.onset) overlaps LookBackInterval
      or C.assertedDate.value in LookBackInterval
      // TODO Confirm these are the correct fields to use

// -------------------------------------------------- PROCEDURES -------------------------------------------------------

 /**
  * Filters Procedures by a concept rather than by a ValueSet.  In CQL 1.3, this will be built into the retrieve,
  * but for now, we must use a query where clause.
  * @param Koncept - the concept to filter on (intentionally mispelled to avoid naming clashes)
  * @returns {List<Procedure>} a list of Procedures matching the concept, or null if null was passed in
  */
 define function ProceduresByConcept(Koncept System.Concept):
   [Procedure] P where NullSafeToConcept(P.code) ~ Koncept

/**
 * Procedures that are completed. In FHIR STU3, this is reflected by status: 'completed'.  In addition, the
 * notDone flag must be checked to ensure it is not 'true'.
 * @see https://www.hl7.org/fhir/STU3/valueset-event-status.html
 * @param ProcList - a list of Procedures
 * @returns {List<Procedure>} a list of completed Procedures, or null if null was passed in
 */
define function Completed(ProcList List<Procedure>):
  ProcList P
    where P.status.value = 'completed'
      and P.notDone.value is not true

/**
 * Procedures that are in progress. In FHIR STU3, this is reflected by status: 'in-progress'.  In addition, the
 * notDone flag must be checked to ensure it is not 'true'.
 * @see https://www.hl7.org/fhir/STU3/valueset-event-status.html
 * @param ProcList - a list of Procedures
 * @returns {List<Procedure>} a list of completed Procedures, or null if null was passed in
 */
define function ProcedureInProgress(ProcList List<Procedure>):
  ProcList P
    where P.status.value = 'in-progress'
      and P.notDone.value is not true

/**
 * Procedures that actually happened or are happening. In FHIR STU3, there are a few properties that negate the
 * procedure, most notably when status is 'entered-in-error' or notDone is true.
 * @see https://www.hl7.org/fhir/STU3/valueset-event-status.html
 * @param ProcList - a list of Procedures
 * @returns {List<Procedure>} a list of Procedures that actually happened or are happening, or null if null was passed in
 */
define function ProcedurePerformance(ProcList List<Procedure>):
  ProcList P
    where P.status.value != 'entered-in-error'
      and P.notDone.value is not true

/**
 * Procedures performed in the specified "look back" period.  For example, PCIs performed in the
 * past 2 weeks.
 * TODO: Rename to LookBack once the execution engine supports overloaded functions.
 * @param ProcList - a list of Procedures
 * @param LookBack - the lookback period for when the procedure was performed
 * @returns {List<Procedure>} a list of Procedures performed in the look back period, or null if null
 * was passed in
 */
define function ProcedureLookBack(ProcList List<Procedure>, LookBack System.Quantity):
  ProcList P
    let LookBackInterval: Interval[Now() - LookBack, Now()]
    where P.performed.value in LookBackInterval
      or NullSafeToInterval(P.performed) overlaps LookBackInterval

// ---------------------------------------------- PROCEDUREREQUESTS ----------------------------------------------------

 /**
  * Filters ProcedureRequests by a concept rather than by a ValueSet.  In CQL 1.3, this will be built into the retrieve,
  * but for now, we must use a query where clause.
  * @param Koncept - the concept to filter on (intentionally mispelled to avoid naming clashes)
  * @returns {List<ProcedureRequest>} a list of ProcedureRequests matching the concept, or null if null was passed in
  */
 define function ProcedureRequestsByConcept(Koncept System.Concept):
   [ProcedureRequest] P where NullSafeToConcept(P.code) ~ Koncept

/**
 * ProcedureRequests that are accepted, in progress, or completed. In FHIR STU3, this is reflected by the corresponding
 * status status values.
 * @see https://www.hl7.org/fhir/STU3/valueset-request-status.html
 * @param ProcReqList - a list of ProcedureRequests
 * @returns {List<ProcedureRequest>} a list of accepted, in-progress, or completed ProcedureRequests,
 * or null if null was passed in
 */
define function ProcedureRequestAcceptedOrInProgressOrCompleted(ProcReqList List<ProcedureRequest>):
  ProcReqList P
    where P.status.value in List{'accepted', 'in-progress', 'completed'}

/**
 * ProcedureRequests ordered in the specified "look back" period.  For example, PCIs ordered in the
 * past 2 weeks.
 * TODO: Rename to LookBack once the execution engine supports overloaded functions.
 * @param ProcReqList - a list of ProcedureRequests
 * @param LookBack - the lookback period for when the procedure was ordered
 * @returns {List<ProcedureRequest>} a list of ProcedureRequests ordered in the look back period, or null if null
 * was passed in
 */
define function ProcedureRequestLookBack(ProcReqList List<ProcedureRequest>, LookBack System.Quantity):
  ProcReqList P
    where P.authoredOn.value in Interval[Now() - LookBack, Now()]

// ----------------------------------------------- REFERRALREQUESTS ----------------------------------------------------

 /**
  * Filters ReferralRequests by a concept rather than by a ValueSet.  In CQL 1.3, this will be built into the retrieve,
  * but for now, we must use a query where clause.
  * @param Koncept - the concept to filter on (intentionally mispelled to avoid naming clashes)
  * @returns {List<ReferralRequest>} a list of ReferralRequests matching the concept, or null if null was passed in
  */
 define function ReferralRequestsByServiceRequestedConcept(Koncept System.Concept):
   [ReferralRequest] R
   where exists((R.serviceRequested) SRC where NullSafeToConcept(SRC) ~ Koncept)

/**
 * ReferralRequests that are accepted, active, or completed. In FHIR STU3, this is reflected by the corresponding
 * status status values.
 * @see https://www.hl7.org/fhir/STU3/valueset-request-status.html
 * @param ReferralList - a list of ReferralRequests
 * @returns {List<ReferralRequest>} a list of accepted, active, or completed ReferralRequests,
 * or null if null was passed in
 */
define function ReferralRequestAcceptedOrActiveOrCompleted(ReferralList List<ReferralRequest>):
  ReferralList R
    where R.status.value in List{'accepted', 'active', 'completed'}

/**
 * ReferralRequests requested in the specified "look back" period.  For example, pace make insertions referrals sent
 * in the past 2 weeks.
 * TODO: Rename to LookBack once the execution engine supports overloaded functions.
 * @param ReferralList - a list of ReferralRequests
 * @param LookBack - the lookback period for when the referral was sent
 * @returns {List<ReferralRequest>} a list of ReferralRequests sent in the look back period, or null if null
 * was passed in
 */
define function ReferralRequestLookBack(ReferralList List<ReferralRequest>, LookBack System.Quantity):
  ReferralList R
    where R.authoredOn.value in Interval[Now() - LookBack, Now()]

// -------------------------------------------------- MEDICATIONS ------------------------------------------------------

/**
 * Filters MedicationStatements by a concept rather than by a ValueSet.  In CQL 1.3, this will be built into the retrieve,
 * but for now, we must use a query where clause.
 * @param Koncept - the concept to filter on (intentionally mispelled to avoid naming clashes)
 * @returns {List<MedicationStatement>} a list of MedicationStatement matching the concept, or null if null was passed in
 */
define function MedicationStatementsByConcept(Koncept System.Concept):
  [MedicationStatement] M where NullSafeToConcept(M.medication) ~ Koncept

/**
 * Filters MedicationRequests by a concept rather than by a ValueSet.  In CQL 1.3, this will be built into the retrieve,
 * but for now, we must use a query where clause.
 * @param Koncept - the concept to filter on (intentionally mispelled to avoid naming clashes)
 * @returns {List<MedicationRequest>} a list of MedicationRequests matching the concept, or null if null was passed in
 */
define function MedicationRequestsByConcept(Koncept System.Concept):
  [MedicationRequest] M where NullSafeToConcept(M.medication) ~ Koncept

/**
 * Medications that are active, according to a statement, but not necessarily verified via a prescription.  For example,
 * medications that a patient has self-reported to be taking.  In FHIR STU3, this is reflected by MedicationStatement
 * with status 'active', no flag indicating it wasn't taken, and no end date or an end date in the future.
 * TODO: Rename to Active once the execution engine supports overloaded functions.
 * @see https://www.hl7.org/fhir/STU3/valueset-medication-statement-status.html
 * @param MedList - a list of MedicationStatements
 * @returns {List<MedicationStatement>} a list of active medication statements, or null if null was passed in
 */
define function ActiveMedicationStatement(MedList List<MedicationStatement>):
  MedList M
    let EffectivePeriod: NullSafeToInterval(M.effective)
    where M.status.value = 'active'
      and M.taken.value != 'n'
      and (end of EffectivePeriod is null or end of EffectivePeriod after Now())

/**
 * Medications that are active or completed, according to a statement, but not necessarily verified via a prescription.
 * For example, medications that a patient has self-reported to be taking.  In FHIR STU3, this is reflected by
 * MedicationStatement with status 'active' or 'completed', and no flag indicating it wasn't taken.
 * TODO: Rename to ActiveOrCompleted once the execution engine supports overloaded functions.
 * @see https://www.hl7.org/fhir/STU3/valueset-medication-statement-status.html
 * @param MedList - a list of MedicationStatements
 * @returns {List<MedicationStatement>} a list of active or completed medication statements, or null if null was passed
 *   in
 */
define function ActiveOrCompletedMedicationStatement(MedList List<MedicationStatement>):
  MedList M
    where M.status.value = 'active'
      or M.status.value = 'completed'
      and M.taken.value != 'n'

/**
* Medications that are active, according to a prescription.  In FHIR STU3, this is reflected by MedicationRequest
* with status 'active' and no dateEnded.  There is currently an open question in the FHIR chat to determine if this
* is the right approach.
* @see https://www.hl7.org/fhir/STU3/valueset-medication-request-status.html
* @param MedList - a list of MedicationRequests
* @returns {List<MedicationRequest>} a list of active medication orders, or null if null was passed in
*/
define function ActiveMedicationRequest(MedList List<MedicationRequest>):
  MedList M
    where M.status.value = 'active'

/**
* Medications that are active or completed, according to a prescription.  In FHIR STU3, this is reflected by MedicationRequest
* with status 'active' or 'completed'
* @see https://www.hl7.org/fhir/STU3/valueset-medication-request-status.html
* @param MedList - a list of MedicationRequests
* @returns {List<MedicationRequest>} a list of active medication orders, or null if null was passed in
*/
define function ActiveOrCompletedMedicationRequest(MedList List<MedicationRequest>):
  MedList M
    where M.status.value = 'active'
      or M.status.value = 'completed'

/**
* Medications that are active, completed, or stopped, according to a prescription.  In FHIR STU3, this is reflected by
* MedicationRequest with status 'active', 'completed', or 'stopped'
* @see https://www.hl7.org/fhir/STU3/valueset-medication-request-status.html
* @param MedList - a list of MedicationRequests
* @returns {List<MedicationRequest>} a list of active medication orders, or null if null was passed in
*/
define function ActiveCompletedOrStoppedMedicationRequest(MedList List<MedicationRequest>):
  MedList M
    where M.status.value = 'active'
      or M.status.value = 'completed'
      or M.status.value = 'stopped'

/**
 * MedicationStatement with an effective date in the specified "look back" period.  For example, statements about opioid
 * use in the last 180 days.
 * TODO: Rename to LookBack once the execution engine supports overloaded functions.
 * @param MedList - a list of MedicationStatements
 * @param LookBack - a duration Quantity indicating how far back to look for MedicationStatements
 * @returns {List<MedicationStatement>} a list of MedicationStatements with effective date in the specified lookback
 * period, or null if null was passed in
 */
define function MedicationStatementLookBack(MedList List<MedicationStatement>, LookBack System.Quantity):
  MedList M
    let LookBackInterval: Interval[Now() - LookBack, Now()]
    where M.effective.value in LookBackInterval
      or NullSafeToInterval(M.effective) overlaps LookBackInterval

/**
 * MedicationRequests with a written date in the specified "look back" period.  For example, opioid orders in the last
 * 180 days.
 * TODO: Rename to LookBack once the execution engine supports overloaded functions.
 * @param OrderList - a list of MedicationRequests
 * @param LookBack - a duration Quantity indicating how far back to look for MedicationRequests
 * @returns {List<MedicationRequest>} a list of MedicationRequests with written date in the specified lookback period,
 * or null if null was passed in
 */
define function MedicationRequestLookBack(MedList List<MedicationRequest>, LookBack System.Quantity):
  MedList M where M.authoredOn.value in Interval[Now() - LookBack, Now()]

// -------------------------------------------------- ENCOUNTERS ------------------------------------------------------

/**
 * Filters Encounters by a concept rather than by a ValueSet.  In CQL 1.3, this will be built into the retrieve,
 * but for now, we must use a query where clause.
 * @param Koncept - the concept to filter on (intentionally mispelled to avoid naming clashes)
 * @returns {List<Encounter>} a list of Encounters matching the concept, or null if null was passed in
 */
define function EncountersByConcept(Koncept System.Concept):
  [Encounter] E where exists( (E.type) ET where NullSafeToConcept(ET) ~ Koncept )

/**
 * Encounters that are in progress. In FHIR STU3, this is reflected by status: 'in-progress'.
 * @see https://www.hl7.org/fhir/STU3/valueset-encounter-status.html
 * @param EncList - a list of Encounters
 * @returns {List<Encounter>} a list of in progress encounters, or null if null was passed in
 */
define function InProgress(EncList List<Encounter>):
  EncList E
    where E.status.value = 'in-progress'

/**
 * Encounters that have not been cancelled. In FHIR STU3, this is reflected by  andy status other 
 * than: 'cancelled'.
 * @see https://www.hl7.org/fhir/STU3/valueset-encounter-status.html
 * @param EncList - a list of Encounters
 * @returns {List<Encounter>} a list of in progress encounters, or null if null was passed in
 */
define function NotCancelled(EncList List<Encounter>):
  EncList E
    where E.status.value != 'cancelled'

/**
 * Encounters performed in the specified "look back" period.
 * TODO: Rename to LookBack once the execution engine supports overloaded functions.
 * @param EncList - a list of Encounters
 * @param LookBack - the lookback period for when the encounter occurred
 * @returns {List<Encounter>} a list of Encounters occurring during the look back period, or null if null
 * was passed in
 */
define function EncounterLookBack(EncList List<Encounter>, LookBack System.Quantity):
  EncList E
    let LookBackInterval: Interval[Now() - LookBack, Now()]
    where NullSafeToInterval(E.period) overlaps LookBackInterval

// -------------------------------------------------- ALLERGY INTOLERANCES ---------------------------------------------

/**
 * Filters AllergyIntolerances by a concept rather than by a ValueSet.  In CQL 1.3, this will be built into the retrieve,
 * but for now, we must use a query where clause.
 * @param Koncept - the concept to filter on (intentionally mispelled to avoid naming clashes)
 * @returns {List<AllergyIntolerance>} a list of Allergy Intolerances matching the concept, or null if null was passed in
 */
define function AllergyIntolerancesByConcept(Koncept System.Concept):
  [AllergyIntolerance] A where NullSafeToConcept(A.code) ~ Koncept

/**
* AllergyIntolerances that are active or confirmed.  In FHIR STU3, this is reflected by AllergyIntolerance
* with status 'active' or 'confirmed'
* @see https://www.hl7.org/fhir/STU3/valueset-allergy-verification-status.html
* @param AllergyIntolList - a list of AllergyIntolerances
* @returns {List<AllergyIntolerance>} a list of active or confirmed allergy intolerances, or null if null was passed in
*/
define function ConfirmedAllergyIntolerance(AllergyIntolList List<AllergyIntolerance>):
  AllergyIntolList A
    where A.verificationStatus.value = 'confirmed'

// -------------------------------------------------------- GOALS ------------------------------------------------------

/**
 * Goals with a start, target, or status date in the specified "look back" period.  For example, Pain Management Goals
 * in the last 2 years.
 * TODO: Rename to LookBack once the execution engine supports overloaded functions.
 * @param GoalList - a list of Goals
 * @returns {List<Goal>} a list of Goals with a start, target, or status date in the specified lookback period, or null
 * if null was passed in
 */
define function GoalLookBack(GoalList List<Goal>, LookBack System.Quantity):
  GoalList G
    let LookBackInterval: Interval[Now() - LookBack, Now()]
    where G.start.value in LookBackInterval
      or G.target.dueD.value in LookBackInterval
      or G.start.value in LookBackInterval
      or G.statusDate.value in LookBackInterval
