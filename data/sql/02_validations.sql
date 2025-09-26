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

