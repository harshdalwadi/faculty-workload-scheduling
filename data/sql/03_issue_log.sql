use FacultyManagement;

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


IF OBJECT_ID('dbo.v_exceptions_open') IS NOT NULL
  DROP VIEW dbo.v_exceptions_open;

CREATE VIEW dbo.v_exceptions_open AS
SELECT
  IssueID,
  RuleName,
  Severity,
  TableName,
  RowKey,
  Details,
  DetectedOn,
  Status
FROM dbo.issue_log
WHERE Status = 'Open';

