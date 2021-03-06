RAISERROR('Create function: [dbo].[ufn_mpObjectQuoteName]', 10, 1) WITH NOWAIT
GO
IF  EXISTS (SELECT * FROM sysobjects WHERE id = OBJECT_ID(N'[dbo].[ufn_mpObjectQuoteName]') AND xtype in (N'FN', N'IF', N'TF', N'FS', N'FT'))
DROP FUNCTION [dbo].[ufn_mpObjectQuoteName]
GO

CREATE FUNCTION [dbo].[ufn_mpObjectQuoteName]
(		
	@objectName	[sysname]
)
RETURNS [sysname]
/* WITH ENCRYPTION */
AS

-- ============================================================================
-- Copyright (c) 2004-2017 Dan Andrei STEFAN (danandrei.stefan@gmail.com)
-- ============================================================================
-- Author			 : Dan Andrei STEFAN
-- Create date		 : 2004-2017
-- Module			 : Database Analysis & Performance Monitoring
-- ============================================================================

begin
	DECLARE   @quoteCharStart	[varchar](1)
			, @quoteCharEnd		[varchar](1)

	SET @quoteCharStart	= '['
	SET @quoteCharEnd	= ']'

	IF CHARINDEX(']', @objectName)<>0 OR CHARINDEX(']', @objectName)<>0
		begin
			SET @quoteCharStart	= '"'
			SET @quoteCharEnd	= '"'								
		end

	RETURN (@quoteCharStart + @objectName + @quoteCharEnd)
end
GO
