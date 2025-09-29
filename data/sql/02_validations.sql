use FacultyManagement;

-- =========================================
-- FR-01: Overload Detection
-- =========================================

INSERT INTO dbo.issue_log (RuleName,Severity,TableName,RowKey,Details)
SELECT
  'Overload' AS RuleName,
  'High' AS Severity,
  'campus_sections_assignments' AS TableName,
  ca.FacultyID as RowKey,
  CONCAT('Assigned ', SUM(TRY_CONVERT(DECIMAL(10,2), ca.ScheduledHoursPerWeek)),
		 ' > Maxload ', cf.[MaxLoadHoursPerWeek]) as Details
from [dbo].[campus_sections_assignments] as ca
JOIN [dbo].[campus_faculty] as cf
	 on ca.FacultyID = cf.FacultyID
group by ca.FacultyID, cf.MaxLoadHoursPerWeek
having SUM(TRY_CONVERT(DECIMAL(10,2), ca.ScheduledHoursPerWeek)) > cf.MaxLoadHoursPerWeek;

-- =========================================
-- FR-03: Unassigned Sections
-- =========================================
insert into [dbo].[issue_log]
(RuleName,Severity,TableName,RowKey,Details)
select
	'Unassigned' AS RuleName,
	'High' AS Severity,
	'campus_sections_assignments' AS TableName,
	a.[FacultyID] as RowKey,
	case
		when
			a.[FacultyID] is null or LTRIM(RTRIM(a.[FacultyID])) = ''
		then
			'Missing Faculty ID'
		else
			CONCAT('Invalid FacultyID: ', a.[FacultyID], ' (not found in campus_faculty)')
	end as Details
from [dbo].[campus_sections_assignments] as a
left join [dbo].[campus_faculty] as f
	on LTRIM(RTRIM(a.[FacultyID])) = LTRIM(RTRIM(f.[FacultyID]))
where
	a.[FacultyID] is null 
	or LTRIM(RTRIM(a.[FacultyID]))=''
	or (
		f.[FacultyID] is null
		and a.[FacultyID] is not null
		and LTRIM(RTRIM(a.FacultyID)) <> ''
	);

-- =========================================
-- FR-02: Department Mismatch
-- =========================================
INSERT INTO [dbo].[issue_log] (RuleName, Severity, TableName, RowKey, Details)
SELECT 
	'DepartmentMismatch' AS RuleName,
	'Medium' AS Severity,
	'campus_sections_assignments' AS TableName,
	a.[SectionID] AS RowKey,
	CONCAT('FacultyDept=', UPPER(LTRIM(RTRIM(f.Department))),
		   '; CourseDept=', UPPER(LTRIM(RTRIM(c.Department))),
		   '; FacultyID=', a.FacultyID,
		   '; CourseCode=', a.CourseCode) AS Details
FROM [dbo].[campus_sections_assignments] as a
join [dbo].[campus_faculty] as f
	on LTRIM(RTRIM(a.[FacultyID])) = LTRIM(RTRIM(f.[FacultyID]))
join [dbo].[campus_courses] as c
	on LTRIM(RTRIM(a.[CourseCode])) = LTRIM(RTRIM(c.[CourseCode]))
where 
  f.Department IS NOT NULL 
  AND c.Department IS NOT NULL
  AND LTRIM(RTRIM(f.Department)) <> '' 
  AND LTRIM(RTRIM(c.Department)) <> ''
  AND UPPER(LTRIM(RTRIM(f.Department))) <> UPPER(LTRIM(RTRIM(c.Department)));

-- =========================================
-- FR-04(a): Duplicates
-- =========================================

INSERT INTO dbo.issue_log (RuleName, Severity, TableName, RowKey, Details)
SELECT
	'DuplicateSection' AS RuleName,
    'Medium' AS Severity,
    'campus_sections_assignments' AS TableName,
    a.SectionID AS RowKey,
    CONCAT('SectionID appears ', COUNT(*), ' times') AS Details
FROM dbo.campus_sections_assignments a
GROUP BY a.SectionID
HAVING COUNT(*) > 1;

-- =========================================
-- FR-04(b): Conflicts (time overlaps)
-- =========================================

;WITH Clean AS (
  SELECT
    SectionID,
    FacultyID,
    StartDate AS StartDT,
    EndDate   AS EndDT
  FROM dbo.campus_sections_assignments
  WHERE FacultyID IS NOT NULL AND LTRIM(RTRIM(FacultyID)) <> ''
    AND StartDate IS NOT NULL
    AND EndDate   IS NOT NULL
    AND StartDate < EndDate
)
INSERT INTO dbo.issue_log (RuleName, Severity, TableName, RowKey, Details)
SELECT
  'TimeOverlap' AS RuleName,
  'High'        AS Severity,
  'campus_sections_assignments' AS TableName,
  CONCAT(a.SectionID, '|', b.SectionID) AS RowKey,
  CONCAT(
    'FacultyID=', a.FacultyID,
    '; A=', a.SectionID, ' [', CONVERT(varchar(16), a.StartDT, 120), ' - ', CONVERT(varchar(16), a.EndDT, 120), ']',
    '; B=', b.SectionID, ' [', CONVERT(varchar(16), b.StartDT, 120), ' - ', CONVERT(varchar(16), b.EndDT, 120), ']'
  ) AS Details
FROM Clean a
JOIN Clean b
  ON a.FacultyID = b.FacultyID
 AND a.SectionID < b.SectionID
WHERE a.StartDT < b.EndDT
  AND b.StartDT < a.EndDT
  AND NOT EXISTS (
        SELECT 1
        FROM dbo.issue_log il
        WHERE il.RuleName = 'TimeOverlap'
          AND il.TableName = 'campus_sections_assignments'
          AND il.RowKey = CONCAT(a.SectionID, '|', b.SectionID)
  );


