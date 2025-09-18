# Faculty Workload Scheduling – Project Charter & BRD
**Author:** Harsh Dalwadi
**Date:** 2025-09-18

---

## 1) Background & Context
**Business context (University):** Scheduling faculty across terms and campuses requires balancing max load limits, availability, and departmental rules. Manual spreadsheets introduce errors (overloads, duplicates, unassigned sections).  

---

## 2) Problem Statement
- Manual processes lead to scheduling errors and slow reporting cycles.  
- Stakeholders lack a single source of truth to see loads, conflicts, and unassigned sections.  
- Data quality issues (typos, duplicates, nulls) reduce trust.

**One-sentence problem statement:**  
_Our current manual workload process leads to avoidable errors and delays; we need a validated, transparent, and reportable workflow._

---

## 3) Goals & Success Criteria 
- **G1:** Detect and flag overloads and conflicts reliably.  
- **G2:** Provide a dashboard to monitor % load, conflicts, and unassigned sections by term/department.  
- **G3:** Produce BA documentation (BRD, process maps, UAT) suitable for implementation or ERP import.

**Success metrics (examples):**
- 100% of overloads and double-bookings identified in test data.  
- < 3 minutes to identify problem areas per department via dashboard.  
- All priority requirements linked to at least one UAT test case.

---

## 4) Stakeholders & RACI
| Role | Name/Team | Responsibility | Responsible | Accountable | Consulted | Informed |
|---|---|---|---|---|---|---|
| Academic Operations Lead | Harsh | Owns scheduling policy |  | **A** | **C** | **I** |
| Department Chairs | Harsh | Validate loads & assignments | **R** |  | **C** | **I** |
| Registrar/Timetabling | Harsh | Maintains sections & terms | **R** |  | **C** | **I** |
| IT/BA (You) | Harsh | ETL, validation rules, dashboards, BRD/UAT | **R** |  | **C** | **I** |


---

## 5) Scope
**In-scope (MVP):**
- ETL validation of synthetic dataset (overloads, duplicates, unassigned, mismatches, time overlaps).  
- Dashboards in Power BI (term/department filters; drill into faculty).  
- BA artifacts: BRD v0, current/future-state maps, UAT test cases.

**Out-of-scope (MVP):**
- Full ERP deployment.  
- Real SSO/role-based access; production security hardening.  
- Complex room/space optimization.

---

## 6) Assumptions & Constraints
- Synthetic dataset approximates real scheduling patterns and includes deliberate errors.  
- Timeboxed build: focus on clarity, not completeness.  
- Tools available: SQL, Python, Power BI, Visio/draw.io.

---

## 7) High-Level Process (to be detailed in Step 2)
1. Intake/collect source data (faculty, courses, availability, assignments).  
2. Run ETL validations (SQL + Python).  
3. Produce curated/clean tables.  
4. Publish dashboards for stakeholders.  
5. UAT with test cases; iterate.  
6. Prepare ERP import mapping (conceptual).

---

## 8) Functional Requirements
- **FR-01 Overload detection:** System flags faculty with `SUM(ScheduledHours) > MaxLoadHoursPerWeek`.  
- **FR-02 Department mismatch:** Flag assignments where `Faculty.Department != Course.Department` (configurable allow-list).  
- **FR-03 Unassigned sections:** Report any section with null/invalid `FacultyID`.  
- **FR-04 Duplicate/conflict:** Identify duplicate sections and overlapping time assignments for the same faculty.  
- **FR-05 Exception report:** Export exceptions to CSV/Excel for chair review.  
- **FR-06 Dashboard:** Provide term/department filters, RYG indicators for % load, and links to detail.  
- **FR-07 Data lineage:** Track “validated_on”, “rule_name”, “severity” for each exception.  
- **FR-08 Auditability:** Keep a log table of detected issues with timestamps and row identifiers.

---

## 9) Non-Functional Requirements
- **NFR-01 Usability:** Non-technical users can interpret RYG indicators and exception summaries without training.  
- **NFR-02 Performance:** Exception summary loads in < 5 sec for <= 50k rows.  
- **NFR-03 Portability:** All outputs exportable to CSV/Excel for sharing.  
- **NFR-04 Traceability:** Each requirement mapped to UAT test cases.

---

## 10) Data Entities & Definitions
- **Faculty**(FacultyID, Name, Department, MaxLoadHoursPerWeek, Campus, …)  
- **Courses**(CourseCode, Name, Department, Credits, Term, DeliveryMode, …)  
- **Availability**(FacultyID, DayOfWeek, StartTime, EndTime, …)  
- **Assignments**(SectionID, FacultyID, CourseCode, Term, MeetingPattern, ScheduledHours, …)

---

## 11) Reporting Requirements
- Workload utilization (% of max) by faculty/department/term.  
- Overload & conflict summary with drill-down.  
- Unassigned sections list, by department/term.  
- Trend comparison across terms (optional).

---

## 12) UAT Plan Outline (link to detailed UAT in separate file)
- Build test cases for each FR (TC-01 ↔ FR-01, etc.).  
- Record expected vs actual results; track defects.  
- Acceptance: All critical FRs pass; no severity-1 defects open.

---

## 13) Risks & Mitigations
- **R1: Data quality worse than expected** → strengthen validation rules; document assumptions.  
- **R2: Scope creep** → fix MVP scope; backlog extras.  
- **R3: Tooling issues** → have backup (e.g., PostgreSQL if SQL Server fails).

---

## 14) Timeline (example)
- Week 1: BRD v0, process maps, data inspection.  
- Week 2: ETL rules in SQL/Python; first dashboard.  
- Week 3: UAT, polish, portfolio packaging.

---

## 15) Glossary
- **Overload:** Total scheduled hours exceed faculty max weekly load.  
- **Conflict:** Two overlapping assignments for the same faculty.  
- **Unassigned:** Section without a valid faculty allocation.