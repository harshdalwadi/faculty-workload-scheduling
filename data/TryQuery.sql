-- create database FacultyManagement;

use FacultyManagement;

-- data inspection

select top 5 *
from [dbo].[campus_faculty];

select top 5 *
from [dbo].[campus_sections_assignments];

EXEC sp_help 'dbo.campus_faculty';

EXEC sp_help '[dbo].[campus_sections_assignments]';

SELECT name 
FROM sys.columns 
WHERE object_id = OBJECT_ID('dbo.campus_sections_assignments')
  AND name LIKE '%hour%';

-- overload detection (FR-1)

select 
	ca.FacultyID,
	SUM(TRY_CONVERT(DECIMAL(10,2), ca.ScheduledHoursPerWeek)) as TotalAssignedHours,
	cf.[MaxLoadHoursPerWeek]
from [dbo].[campus_sections_assignments] as ca
JOIN [dbo].[campus_faculty] as cf
	 on ca.FacultyID = cf.FacultyID
group by ca.FacultyID, cf.MaxLoadHoursPerWeek
having SUM(TRY_CONVERT(DECIMAL(10,2), ca.ScheduledHoursPerWeek)) > cf.MaxLoadHoursPerWeek;

-- creating issue log table to store these ones
CREATE TABLE dbo.issue_log (
  IssueID    INT IDENTITY(1,1) PRIMARY KEY,
  RuleName   NVARCHAR(50),
  Severity   NVARCHAR(10),
  TableName  NVARCHAR(50),
  RowKey     NVARCHAR(100),
  Details    NVARCHAR(400),
  DetectedOn DATETIME2 DEFAULT SYSDATETIME(),
  Status     NVARCHAR(15) DEFAULT 'Open'
);

-- LOG Overloads
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

-- Check Log
select *
from [dbo].[issue_log];

-- FR-03 check
select top 5 *
from [dbo].[campus_sections_assignments];

select top 5 *
from [dbo].[campus_faculty];

-- null check
select * 
from [dbo].[campus_faculty]
where LTRIM(RTRIM([FacultyID]))= '';

-- invalid FacultyID
SELECT *
from [dbo].[campus_sections_assignments] as ca
left join [dbo].[campus_faculty] as cf
on LTRIM(RTRIM(ca.[FacultyID])) = LTRIM(RTRIM(cf.[FacultyID]))
where ca.[FacultyID] is not null 
and LTRIM(RTRIM(ca.[FacultyID])) <> ''
and cf.[FacultyID] is null;

-- combined
SELECT 
	ca.[FacultyID],
	cf.[FacultyID],
	CASE 
	WHEN cf.[FacultyID] IS NULL OR LTRIM(RTRIM(cf.[FacultyID])) = '' 
			THEN 'Missing FacultyID'
	ELSE 'Invalid FacultyID (not found in campus_faculty)'
	END AS Reason
from [dbo].[campus_sections_assignments] as ca
left join [dbo].[campus_faculty] as cf
	on LTRIM(RTRIM(ca.[FacultyID])) = LTRIM(RTRIM(cf.[FacultyID]))
where 
	cf.[FacultyID] is null
	or LTRIM(RTRIM(cf.[FacultyID])) = ''
	or (ca.[FacultyID] is null 
		and cf.[FacultyID] is not null 
		and LTRIM(RTRIM(cf.[FacultyID]))='');

-- write into log
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
	)

select *
from [dbo].[issue_log];

-- fr-2 check
select top 5 * 
from [dbo].[campus_faculty];

select top 5 * 
from [dbo].[campus_courses];

select top 5 * 
from [dbo].[campus_sections_assignments];

EXEC SP_HELP '[dbo].[campus_courses]';

SELECT 
	a.[SectionID],
	a.[FacultyID],
	a.[CourseCode],
	f.[Department] as FacultyDept,
	c.CourseName as CourseDept
FROM [dbo].[campus_sections_assignments] as a
join [dbo].[campus_faculty] as f
	on LTRIM(RTRIM(a.[FacultyID])) = LTRIM(RTRIM(f.[FacultyID]))
join [dbo].[campus_courses] as c
	on LTRIM(RTRIM(a.[CourseCode])) = LTRIM(RTRIM(c.[CourseCode]));

-- check more with context
SELECT 
	a.[SectionID],
	a.[FacultyID],
	a.[CourseCode],
	UPPER(LTRIM(RTRIM(f.[Department]))) as FacultyDept,
	UPPER(LTRIM(RTRIM(c.CourseName))) as CourseDept
FROM [dbo].[campus_sections_assignments] as a
join [dbo].[campus_faculty] as f
	on LTRIM(RTRIM(a.[FacultyID])) = LTRIM(RTRIM(f.[FacultyID]))
join [dbo].[campus_courses] as c
	on LTRIM(RTRIM(a.[CourseCode])) = LTRIM(RTRIM(c.[CourseCode]))
WHERE
  f.[Department] IS NOT NULL AND LTRIM(RTRIM(f.[Department])) <> ''
  AND c.[Department] IS NOT NULL AND LTRIM(RTRIM(c.[Department])) <> ''
  -- compare after normalization
  AND UPPER(LTRIM(RTRIM(f.[Department]))) <> UPPER(LTRIM(RTRIM(c.[Department]))); 

-- issue log
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
  a.[Department] IS NULL AND LTRIM(RTRIM(a.[Department])) <> ''
  AND c.[Department] IS NULL AND LTRIM(RTRIM(c.[Department])) <> '';

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

select *
FROM dbo.issue_log


SELECT 
    a.SectionID,
    a.FacultyID,
    a.CourseCode,
    f.Department AS FacultyDept,
    c.Department AS CourseDept
FROM dbo.campus_sections_assignments a
JOIN dbo.campus_faculty f
    ON a.FacultyID = f.FacultyID
JOIN dbo.campus_courses c
    ON a.CourseCode = c.CourseCode
WHERE f.Department IS NOT NULL 
  AND c.Department IS NOT NULL
  AND LTRIM(RTRIM(f.Department)) <> '' 
  AND LTRIM(RTRIM(c.Department)) <> ''
  AND UPPER(LTRIM(RTRIM(f.Department))) <> UPPER(LTRIM(RTRIM(c.Department)));

-- Duplicate / Conflict detection
select COUNT(*)
from [dbo].[campus_sections_assignments];

select COUNT(*)
from (
SELECT 
    a.SectionID,
    COUNT(*) AS DuplicateCount
FROM dbo.campus_sections_assignments a
GROUP BY a.SectionID
HAVING COUNT(*) > 1
) as assignments;

SELECT 
    a.SectionID,
    COUNT(*) AS DuplicateCount
FROM dbo.campus_sections_assignments a
GROUP BY a.SectionID
HAVING COUNT(*) > 1;

INSERT INTO dbo.issue_log (RuleName, Severity, TableName, RowKey, Details)
SELECT
    'DuplicateSection' AS RuleName,
    'Medium'           AS Severity,
    'campus_sections_assignments' AS TableName,
    a.SectionID        AS RowKey,
    CONCAT('SectionID appears ', COUNT(*), ' times') AS Details
FROM dbo.campus_sections_assignments a
GROUP BY a.SectionID
HAVING COUNT(*) > 1;

-- conflict detection
select top 5 *
from [dbo].[campus_sections_assignments];

exec sp_help '[dbo].[campus_sections_assignments]';

SELECT TOP 20
  SectionID,
  FacultyID,
  StartDate,
  EndDate
FROM dbo.campus_sections_assignments;

SELECT TOP 20
  SectionID,
  FacultyID,
  StartDate,
  EndDate
FROM [dbo].[campus_sections_assignments] as a
where 
	a.[FacultyID] is not null and LTRIM(RTRIM(a.[FacultyID]))<>''
	and a.[StartDate] is not null
	and a.[EndDate] is not null
	and a.[StartDate] < a.[EndDate];

WITH Clean AS (
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
SELECT
  a.FacultyID,
  a.SectionID AS A_Section,
  a.StartDT   AS A_Start,
  a.EndDT     AS A_End,
  b.SectionID AS B_Section,
  b.StartDT   AS B_Start,
  b.EndDT     AS B_End
FROM Clean a
JOIN Clean b
  ON a.FacultyID = b.FacultyID 
 AND a.SectionID < b.SectionID;

WITH Clean AS (
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
SELECT
  a.FacultyID,
  a.SectionID AS A_Section, a.StartDT AS A_Start, a.EndDT AS A_End,
  b.SectionID AS B_Section, b.StartDT AS B_Start, b.EndDT AS B_End
FROM Clean a
JOIN Clean b
  ON a.FacultyID = b.FacultyID
 AND a.SectionID < b.SectionID
WHERE a.StartDT < b.EndDT    -- overlap rule part 1
  AND b.StartDT < a.EndDT;   -- overlap rule part 2

-- Make sure the previous statement ended with a semicolon.
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
    AND StartDate < EndDate      -- sanity: start before end
)
SELECT
  a.FacultyID,
  a.SectionID AS A_Section, a.StartDT AS A_Start, a.EndDT AS A_End,
  b.SectionID AS B_Section, b.StartDT AS B_Start, b.EndDT AS B_End
FROM Clean a
JOIN Clean b
  ON a.FacultyID = b.FacultyID
 AND a.SectionID < b.SectionID          -- compare each pair once
WHERE a.StartDT < b.EndDT                -- overlap rule (part 1)
  AND b.StartDT < a.EndDT;               -- overlap rule (part 2)

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
  AND NOT EXISTS (                      -- avoid double-logging
        SELECT 1
        FROM dbo.issue_log il
        WHERE il.RuleName = 'TimeOverlap'
          AND il.TableName = 'campus_sections_assignments'
          AND il.RowKey = CONCAT(a.SectionID, '|', b.SectionID)
  );


  delete from [dbo].[issue_log];