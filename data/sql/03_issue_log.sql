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