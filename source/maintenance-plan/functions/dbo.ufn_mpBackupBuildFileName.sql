RAISERROR('Create function: [dbo].[ufn_mpBackupBuildFileName]', 10, 1) WITH NOWAIT
GO
IF  EXISTS (SELECT * FROM sysobjects WHERE id = OBJECT_ID(N'[dbo].[ufn_mpBackupBuildFileName]') AND xtype in (N'FN', N'IF', N'TF', N'FS', N'FT'))
DROP FUNCTION [dbo].[ufn_mpBackupBuildFileName]
GO

CREATE FUNCTION [dbo].[ufn_mpBackupBuildFileName]
(		
	@sqlServerName			[sysname],
	@dbName					[sysname],
	@backupType				[nvarchar](8) /* FULL, DIFF, LOG */,
	@currentDate			[datetime]
)
RETURNS [nvarchar](1024)
/* WITH ENCRYPTION */
AS

-- ============================================================================
-- Copyright (c) 2004-2015 Dan Andrei STEFAN (danandrei.stefan@gmail.com)
-- ============================================================================
-- Author			 : Dan Andrei STEFAN
-- Create date		 : 2004-2006
-- Module			 : Database Analysis & Performance Monitoring
-- ============================================================================

begin
	/* file name format: ServerName_DBName_yyyymmdd_hhmmss_BackupType.Ext */
	DECLARE @backupFileName	[nvarchar](1024)
	
	SET @backupFileName=''

	--ServerName token
	SET @backupFileName=@backupFileName + REPLACE(@sqlServerName, '\', '$')
	SET @backupFileName=@backupFileName +  '_'
	
	--DBName token
	SET @backupFileName=@backupFileName + @dbName
	SET @backupFileName=@backupFileName +  '_'

	--Date token: yyyymmdd
	SET @backupFileName=@backupFileName + CONVERT([nvarchar](8), @currentDate, 112)
	SET @backupFileName=@backupFileName +  '_'

	--Time token: hhmmss
	SET @backupFileName=@backupFileName + REPLACE(CONVERT([nvarchar](8), @currentDate, 114), ':', '')
	SET @backupFileName=@backupFileName +  '_'

	--BackupType token
	SET @backupFileName=@backupFileName + LOWER(@backupType)

	--File Extension token
	SET @backupFileName=@backupFileName + '.' + CASE WHEN LOWER(@backupType) IN ('full', 'diff') THEN N'BAK' 
													 WHEN LOWER(@backupType) IN ('log') THEN N'TRN'
													 ELSE 'BKP'
												END

	RETURN @backupFileName
end
GO
