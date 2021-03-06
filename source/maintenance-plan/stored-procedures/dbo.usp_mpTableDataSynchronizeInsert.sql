RAISERROR('Create procedure: [dbo].[usp_mpTableDataSynchronizeInsert]', 10, 1) WITH NOWAIT
GO
SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

if exists (select * from dbo.sysobjects where id = object_id(N'[dbo].[usp_mpTableDataSynchronizeInsert]') and OBJECTPROPERTY(id, N'IsProcedure') = 1)
drop procedure [dbo].[usp_mpTableDataSynchronizeInsert]
GO

CREATE PROCEDURE [dbo].[usp_mpTableDataSynchronizeInsert]
		@sourceServerName		[sysname]=@@SERVERNAME,
		@sourceDB				[sysname],			
		@sourceTableSchema		[sysname]='%',
		@sourceTableName		[sysname]='%',
		@destinationServerName	[sysname]=@@SERVERNAME,
		@destinationDB			[sysname],			
		@destinationTableSchema	[sysname]='%',		
		@destinationTableName	[sysname]='%',		
		@flgActions				[smallint] = 1,
		@flgOptions				[int] = 10328,
		@allowDataLoss			[bit]=0,
		@executionLevel			[tinyint] = 0,
		@debugMode				[bit]=0
/* WITH ENCRYPTION */
AS

-- ============================================================================
-- Copyright (c) 2004-2015 Dan Andrei STEFAN (danandrei.stefan@gmail.com)
-- ============================================================================
-- Author			 : Dan Andrei STEFAN
-- Create date: 2004-2006, last updated 04.02.2015
-- Module     : Database Maintenance Scripts
-- ============================================================================
---------------------------------------------------------------------------------------------
--		@flgActions		 1  - Copy records from Sources to Destination (default)
--						 2  - perform truncate on Destination before copy
---------------------------------------------------------------------------------------------
--		@flgOptions		 8  - Disable non-clustered index (default)
--						16  - Disable all foreign key constraints that reffered current table before rebuilding indexes (default)
--						64  - When enabling foreign key constraints, do no check values. Default behaviour is to enabled foreign key constraint with check option
--					  2048  - send email when a error occurs (default)
--					  8192  - disable/enable table triggers (default)
---------------------------------------------------------------------------------------------

DECLARE	@tmpServerDestination		[varchar](1024),
		@queryToRun					[nvarchar](4000),
		@queryToRun1				[nvarchar](4000),
		@columnName					[sysname],
		@columnType					[sysname],
		@tmpCount					[int],
		@tmpCount1					[int],
		@tmpCount2					[int],
		@tableHasBlobs				[bit],
		@flgSkipSynchronizeInsert	[bit],
		@ReturnValue				[int],
		@nestExecutionLevel			[tinyint],
		@flgOptionsNested			[int],
		@affectedDependentObjects	[nvarchar](max)


DECLARE @schemaNameSource		[sysname],
		@schemaNameDestination	[sysname],
		@tableNameSource		[sysname],
		@tableNameDestination	[sysname],
		@columnSource			[sysname],
		@columnDestination		[sysname]


IF object_id('#tmpDBSource') IS NOT NULL DROP TABLE #tmpDBSource
CREATE TABLE #tmpDBSource 
		(
			[table_schema]	[sysname],
			[table_name]	[sysname]
		)

IF object_id('#tmpDBDestination') IS NOT NULL DROP TABLE #tmpDBDestination
CREATE TABLE #tmpDBDestination 
		(
			[table_schema]	[sysname],
			[table_name]	[sysname]
		)

IF object_id('#tmpDBMixed') IS NOT NULL DROP TABLE #tmpDBMixed
CREATE TABLE #tmpDBMixed 
		(
			[source_table_schema]		[sysname],
			[source_table_name]			[sysname],
			[destination_table_schema]	[sysname],
			[destination_table_name]	[sysname]
		)

IF object_id('#tmpTableColumnsBlobs') IS NOT NULL DROP TABLE #tmpTableColumnsBlobs
CREATE TABLE #tmpTableColumnsBlobs 
		(
			ColumnName varchar(255), 
			ColumnType varchar(255)
		)

IF object_id('#tmpTableColumnsSource') IS NOT NULL DROP TABLE #tmpTableColumnsSource
CREATE TABLE #tmpTableColumnsSource 
		(
			ColumnName varchar(255)
		)

IF object_id('#tmpTableColumnsDestination') IS NOT NULL DROP TABLE #tmpTableColumnsDestination
CREATE TABLE #tmpTableColumnsDestination 
		(
			ColumnName varchar(255)
		)

IF object_id('#tmpTableColumnsMixed') IS NOT NULL DROP TABLE #tmpTableColumnsMixed
CREATE TABLE #tmpTableColumnsMixed 
		(
			ColumnSource varchar(255), 
			ColumnDestination varchar(255)
		)

IF object_id('#tmpCount') IS NOT NULL DROP TABLE #tmpCount
CREATE TABLE #tmpCount 
		(
			[result] int
		)



-----------------------------------------------------------------------------------------------------------------------------------------
SET NOCOUNT ON
-----------------------------------------------------------------------------------------------------------------------------------------
-- { sql_statement | statement_block }
BEGIN TRY
		SET @ReturnValue	 = 0
		SET @tmpServerDestination	='[' + @destinationServerName + '].[' + @destinationDB + '].[dbo].sp_executesql'

		-----------------------------------------------------------------------------------------------------------------------------------------
		--get source database table information
		SET @queryToRun = N''
		SET @queryToRun = @queryToRun + N'SELECT TABLE_SCHEMA, TABLE_NAME 
										FROM [' + @sourceDB + '].INFORMATION_SCHEMA.TABLES 
										WHERE TABLE_TYPE = ''BASE TABLE'' 
												AND TABLE_SCHEMA LIKE ''' + @sourceTableSchema + '''
												AND TABLE_NAME LIKE ''' + @sourceTableName + ''''
		SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sourceServerName, @queryToRun)
		IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = @executionLevel, @messageTreelevel = 0, @stopExecution=0

		INSERT	INTO #tmpDBSource ([table_schema], [table_name])
				EXEC (@queryToRun)
		SELECT @tmpCount1=count(*) from #tmpDBSource

		-----------------------------------------------------------------------------------------------------------------------------------------
		--get destination database table information
		SET @queryToRun = N''
		SET @queryToRun = @queryToRun + N'SELECT TABLE_SCHEMA, TABLE_NAME 
										FROM [' + @destinationDB + '].INFORMATION_SCHEMA.TABLES 
										WHERE TABLE_TYPE = ''BASE TABLE'' 
												AND TABLE_SCHEMA LIKE ''' + @destinationTableSchema + '''
												AND TABLE_NAME LIKE ''' + @destinationTableName + ''''
		SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sourceServerName, @queryToRun)
		IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = @executionLevel, @messageTreelevel = 0, @stopExecution=0

		INSERT	INTO #tmpDBDestination ([table_schema], [table_name])
				EXEC (@queryToRun)
		SELECT @tmpCount2=count(*) from #tmpDBDestination


		-----------------------------------------------------------------------------------------------------------------------------------------
		--operatiunile de import date bulk se vor face numai pe tabelele comune celor 2 baze, sursa si destinatie
		IF @sourceTableSchema<>'%' AND @sourceTableName<>'%' AND @destinationTableSchema<>'%' AND @destinationTableName<>'%'
			SET @queryToRun=   'SELECT ''' + @sourceTableSchema + ''' AS [source_table_schema], ''' + @sourceTableName + ''' AS [source_table_name], ''' + @destinationTableSchema + ''' AS [destination_table_schema], ''' + @destinationTableName + ''' AS [destination_table_name]'
		ELSE
			SET @queryToRun=N'SELECT   S.[table_schema]		AS [source_table_schema]
									 , S.[table_name]		AS [source_table_name]
									 , D.[table_schema]		AS [destination_table_schema]
									 , D.[table_name]		AS [destination_table_name] 
							FROM #tmpDBSource AS S 
							INNER JOIN #tmpDBDestination AS D ON S.[table_schema]=D.[table_schema] AND S.[table_name]=D.[table_name]'
		IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = @executionLevel, @messageTreelevel = 0, @stopExecution=0
		INSERT	INTO #tmpDBMixed ([source_table_schema], [source_table_name], [destination_table_schema], [destination_table_name])
				EXEC (@queryToRun)

		-----------------------------------------------------------------------------------------------------------------------------------------
		--analizez tabelele comune din cele 2 baze de date dupa campurile comune
		-----------------------------------------------------------------------------------------------------------------------------------------
		IF @tmpCount1<>0 AND @tmpCount2<>0
			begin
				-----------------------------------------------------------------------------------------------------------------------------------------
				DECLARE crsDBMixed CURSOR LOCAL FAST_FORWARD FOR	SELECT [source_table_schema], [source_table_name], [destination_table_schema], [destination_table_name]
																	FROM #tmpDBMixed 
																	WHERE 	([destination_table_name] NOT LIKE '%dtproperties%') 
																			AND  ([destination_table_name] NOT LIKE '%sys%') 
																	ORDER BY [source_table_schema], [source_table_name], [destination_table_schema], [destination_table_name]
				OPEN crsDBMixed
				FETCH NEXT FROM crsDBMixed INTO @schemaNameSource, @tableNameSource, @schemaNameDestination, @tableNameDestination
				WHILE @@FETCH_STATUS=0
					begin
						------------------------------------------------------------------------------------------------------------------------
						SET @tableHasBlobs=0
						SET @flgSkipSynchronizeInsert=0
		
						------------------------------------------------------------------------------------------------------------------------
						--pentru fiecare tabela comuna, se vor cauta campurile comune
						SET @queryToRun='Analyze Source: [' + @sourceServerName + '].[' + @sourceDB + '].[' + @schemaNameSource + '].[' + @tableNameSource + '] vs Destination: [' + @destinationServerName + '].[' + @destinationDB + '].[' + @schemaNameDestination + '].' + @tableNameDestination + ']'
						EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = @executionLevel, @messageTreelevel = 1, @stopExecution=0
		
						------------------------------------------------------------------------------------------------------------------------
						SET @queryToRun='SELECT COLUMN_NAME, DATA_TYPE 
										 FROM [' + @sourceDB + '].INFORMATION_SCHEMA.COLUMNS 
										 WHERE TABLE_NAME=''' + @tableNameSource + ''' 
												AND TABLE_SCHEMA=''' + @schemaNameSource + '''
												AND DATA_TYPE IN (''text'', ''ntext'', ''image'')'
						SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sourceServerName, @queryToRun)
						IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = @executionLevel, @messageTreelevel = 0, @stopExecution=0

						TRUNCATE TABLE #tmpTableColumnsBlobs
						INSERT INTO #tmpTableColumnsBlobs ([ColumnName], [ColumnType])
								EXEC (@queryToRun)

						DECLARE crsTableFieldsBlobs CURSOR FOR	SELECT DISTINCT ColumnName, ColumnType 
																FROM #tmpTableColumnsBlobs
						OPEN crsTableFieldsBlobs
						FETCH NEXT FROM crsTableFieldsBlobs INTO @columnName, @columnType
						WHILE @@FETCH_STATUS=0
							begin
								SET @queryToRun='SELECT MAX(DATALENGTH(' + @columnName + ')) FROM [' + @sourceDB + '].[' + @schemaNameSource + '].[' + @tableNameSource + ']'
								SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sourceServerName, @queryToRun)
								IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = @executionLevel, @messageTreelevel = 0, @stopExecution=0
						
								TRUNCATE TABLE #tmpCount
								INSERT	INTO #tmpCount([Result])
										EXEC (@queryToRun)

								IF (SELECT Result FROM #tmpCount)>=8000 
									begin
										DELETE FROM #tmpTableColumnsBlobs WHERE ColumnName=@columnName
										SET @tableHasBlobs=1
									end					
								FETCH NEXT FROM crsTableFieldsBlobs INTO @columnName, @columnType
							end
						CLOSE crsTableFieldsBlobs
						DEALLOCATE crsTableFieldsBlobs
		
						SET @queryToRun='SELECT inf.COLUMN_NAME 
										FROM [' + @sourceDB + '].INFORMATION_SCHEMA.COLUMNS inf
										INNER JOIN (
													SELECT [name] FROM [' + @sourceDB + '].dbo.syscolumns 
													WHERE	[id]=OBJECT_ID(''[' + @sourceDB + '].[' + @schemaNameSource + '].[' + @tableNameSource + ']'') 
															AND [iscomputed]=0
													) cl ON inf.[COLUMN_NAME]=cl.[name]
										WHERE inf.TABLE_NAME=''' + @tableNameSource + ''' 
												AND inf.TABLE_SCHEMA=''' + @schemaNameSource + '''
												AND	inf.DATA_TYPE NOT IN (''text'', ''ntext'', ''image'', ''timestamp'')'
						SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@sourceServerName, @queryToRun)
						IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = @executionLevel, @messageTreelevel = 0, @stopExecution=0

						TRUNCATE TABLE #tmpTableColumnsSource
						INSERT	INTO #tmpTableColumnsSource ([ColumnName])
								EXEC (@queryToRun)

						INSERT INTO #tmpTableColumnsSource SELECT DISTINCT ColumnName FROM #tmpTableColumnsBlobs
				
						IF @tableHasBlobs=1 AND @allowDataLoss=0
							begin
								EXEC [dbo].[usp_logPrintMessage] @customMessage = 'WARNING: Source table contains lob columns that cannot be copied. Skipping...', @raiseErrorAsPrint = 1, @messagRootLevel = @executionLevel, @messageTreelevel = 1, @stopExecution=0
								SET @flgSkipSynchronizeInsert=1
							end
		
						IF @flgSkipSynchronizeInsert=0
							begin
								IF @flgActions & 1 = 1
									begin
										------------------------------------------------------------------------------------------------------------------------
										SET @queryToRun='SELECT COLUMN_NAME, DATA_TYPE 
														 FROM [' + @destinationDB + '].INFORMATION_SCHEMA.COLUMNS 
														 WHERE TABLE_NAME=''' + @tableNameDestination + ''' 
																AND TABLE_SCHEMA=''' + @tableNameDestination + '''
																AND DATA_TYPE IN (''text'', ''ntext'', ''image'')'
										SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@destinationServerName, @queryToRun)
										IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = @executionLevel, @messageTreelevel = 0, @stopExecution=0

										TRUNCATE TABLE #tmpTableColumnsBlobs
										INSERT INTO #tmpTableColumnsBlobs ([ColumnName], [ColumnType])
												EXEC (@queryToRun)
						
										DECLARE crsTableFieldsBlobs CURSOR FOR	SELECT DISTINCT ColumnName, ColumnType 
																				FROM #tmpTableColumnsBlobs
										OPEN crsTableFieldsBlobs
										FETCH NEXT FROM crsTableFieldsBlobs INTO @columnName, @columnType
										WHILE @@FETCH_STATUS=0
											begin
												SET @queryToRun='SELECT MAX(DATALENGTH(' + @columnName + ')) FROM [' + @destinationDB + '].[' + @tableNameDestination + '].[' + @tableNameDestination + ']'
												SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@destinationServerName, @queryToRun)
												IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = @executionLevel, @messageTreelevel = 0, @stopExecution=0
						
												TRUNCATE TABLE #tmpCount
												INSERT	INTO #tmpCount([Result])
														EXEC (@queryToRun)

												IF (SELECT Result FROM #tmpCount)>=8000 
													begin
														DELETE FROM #tmpTableColumnsBlobs WHERE ColumnName=@columnName
													end					
												FETCH NEXT FROM crsTableFieldsBlobs INTO @columnName, @columnType
											end
										CLOSE crsTableFieldsBlobs
										DEALLOCATE crsTableFieldsBlobs
		
										SET @queryToRun='SELECT inf.COLUMN_NAME 
														FROM [' + @destinationDB + '].INFORMATION_SCHEMA.COLUMNS inf
														INNER JOIN (
																	SELECT [name] FROM [' + @destinationDB + '].dbo.syscolumns 
																	WHERE	[id]=OBJECT_ID(''[' + @destinationDB + '].[' + @schemaNameDestination + '].[' + @tableNameDestination + ']'') 
																			AND [iscomputed]=0
																	) cl ON inf.[COLUMN_NAME]=cl.[name]
														WHERE inf.TABLE_NAME=''' + @tableNameDestination + ''' 
																AND inf.TABLE_SCHEMA=''' + @schemaNameDestination + '''
																AND	inf.DATA_TYPE NOT IN (''text'', ''ntext'', ''image'', ''timestamp'')'
										SET @queryToRun = [dbo].[ufn_formatSQLQueryForLinkedServer](@destinationServerName, @queryToRun)
										IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = @executionLevel, @messageTreelevel = 0, @stopExecution=0

										TRUNCATE TABLE #tmpTableColumnsDestination
										INSERT INTO #tmpTableColumnsDestination([ColumnName])
												EXEC (@queryToRun)

										INSERT INTO #tmpTableColumnsDestination SELECT DISTINCT ColumnName FROM #tmpTableColumnsBlobs
		
										------------------------------------------------------------------------------------------------------------------------
										SET @queryToRun='SELECT S.ColumnName AS ColumnSource, D.ColumnName AS ColumnDestination FROM #tmpTableColumnsSource AS S INNER JOIN #tmpTableColumnsDestination AS D ON S.ColumnName=D.ColumnName'
										IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = @executionLevel, @messageTreelevel = 0, @stopExecution=0

										TRUNCATE TABLE #tmpTableColumnsMixed
										INSERT	INTO #tmpTableColumnsMixed ([ColumnSource], [ColumnDestination])
												EXEC (@queryToRun)
									end

								------------------------------------------------------------------------------------------------------------------------
								--disable table non-clustered indexes
								------------------------------------------------------------------------------------------------------------------------
								IF @flgOptions & 8 = 8
									begin
										SET @nestExecutionLevel = @executionLevel + 1
										EXEC [dbo].[usp_mpAlterTableIndexes]	@sqlServerName				= @destinationServerName,
																				@dbName						= @destinationDB,
																				@tableSchema				= @schemaNameDestination,
																				@tableName					= @tableNameDestination,
																				@indexName					= '%',
																				@indexID					= NULL,
																				@partitionNumber			= 1,
																				@flgAction					= 4,
																				@flgOptions					= DEFAULT,
																				@maxDOP						= 1,
																				@executionLevel				= @nestExecutionLevel,
																				@affectedDependentObjects	= @affectedDependentObjects OUT,
																				@debugMode					= @debugMode
										--rebuild PK, we might need it
										EXEC [dbo].[usp_mpAlterTableIndexes]	@sqlServerName				= @destinationServerName,
																				@dbName						= @destinationDB,
																				@tableSchema				= @schemaNameDestination,
																				@tableName					= @tableNameDestination,
																				@indexName					= NULL,
																				@indexID					= 1,
																				@partitionNumber			= 1,
																				@flgAction					= 1,
																				@flgOptions					= DEFAULT,
																				@maxDOP						= 1,
																				@executionLevel				= @nestExecutionLevel,
																				@affectedDependentObjects	= @affectedDependentObjects OUT,
																				@debugMode					= @debugMode
									end

								------------------------------------------------------------------------------------------------------------------------
								--disable table constraints
								------------------------------------------------------------------------------------------------------------------------
								IF @flgOptions & 16 = 16
									begin
										SET @nestExecutionLevel = @executionLevel + 1
										SET @flgOptionsNested = 3 + (@flgOptions & 2048)
										EXEC [dbo].[usp_mpAlterTableForeignKeys]	@sqlServerName		= @destinationServerName ,
																					@dbName				= @destinationDB,
																					@tableSchema		= @schemaNameDestination, 
																					@tableName			= @tableNameDestination,
																					@constraintName		= '%',
																					@flgAction			= 0,
																					@flgOptions			= @flgOptionsNested,
																					@executionLevel		= @nestExecutionLevel,
																					@debugMode			= @debugMode
									end

								------------------------------------------------------------------------------------------------------------------------
								--disable table triggers
								------------------------------------------------------------------------------------------------------------------------
								IF @flgOptions & 8192 = 8192
									begin
										SET @nestExecutionLevel = @executionLevel + 1
										EXEC [dbo].[usp_mpAlterTableTriggers]		@sqlServerName		= @destinationServerName,
																					@dbName				= @destinationDB,
																					@tableSchema		= @schemaNameDestination, 
																					@tableName			= @tableNameDestination,
																					@triggerName		= '%',
																					@flgAction			= 0,
																					@flgOptions			= @flgOptions,
																					@executionLevel		= @nestExecutionLevel,
																					@debugMode			= @debugMode
									end			
								
								---------------------------------------------------------------------------------------------------------
								IF @flgActions & 2 = 2
									begin
										EXEC [dbo].[usp_logPrintMessage] @customMessage = 'Delete Data from Destination - Start', @raiseErrorAsPrint = 1, @messagRootLevel = @executionLevel, @messageTreelevel = 1, @stopExecution=0
	
										--------------------------------------------------------------------------------------------------------
										SET @nestExecutionLevel=@executionLevel+1
										EXEC @tmpCount = [dbo].[usp_tableGetRowCount]	@sqlServerName			= @destinationServerName,
																						@databaseName			= @destinationDB,
																						@schemaName				= @schemaNameDestination,
																						@tableName				= @tableNameDestination,
																						@executionLevel			= @nestExecutionLevel,
																						@debugMode				= @debugMode

										SET @queryToRun1= 'Total Rows In Destination Table Before Delete: ' + CAST(@tmpCount AS varchar(20))
										EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun1, @raiseErrorAsPrint = 1, @messagRootLevel = @executionLevel, @messageTreelevel = 2, @stopExecution=0
								
										--------------------------------------------------------------------------------------------------------
										SET @queryToRun1= 'Deleteting records... '
										EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun1, @raiseErrorAsPrint = 1, @messagRootLevel = @executionLevel, @messageTreelevel = 2, @stopExecution=0

										SET @queryToRun='DELETE FROM [' + @destinationDB + '].[' + @schemaNameDestination + '].[' + @tableNameDestination + ']'
										IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = @executionLevel, @messageTreelevel = 0, @stopExecution=0

										EXEC @tmpServerDestination @queryToRun
										SET @ReturnValue=@@ERROR

										SET @queryToRun='Error Returned: ' + CAST(@ReturnValue AS varchar)
										EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = @executionLevel, @messageTreelevel = 3, @stopExecution=0
										
										--------------------------------------------------------------------------------------------------------
										--update usage
										SET @nestExecutionLevel = @executionLevel + 1
										EXEC [dbo].[usp_mpDatabaseConsistencyCheck]	@SQLServerName			= @destinationServerName,
																					@DBName					= @destinationDB,
																					@TableSchema			= @schemaNameDestination,
																					@TableName				= @tableNameDestination,
																					@flgActions				= 64,
																					@flgOptions				= DEFAULT,
																					@executionLevel			= @nestExecutionLevel,
																					@debugMode				= @debugMode

										--------------------------------------------------------------------------------------------------------
										SET @nestExecutionLevel=@executionLevel+1
										EXEC @tmpCount = [dbo].[usp_tableGetRowCount]	@sqlServerName			= @destinationServerName,
																						@databaseName			= @destinationDB,
																						@schemaName				= @schemaNameDestination,
																						@tableName				= @tableNameDestination,
																						@executionLevel			= @nestExecutionLevel,
																						@debugMode				= @debugMode

										SET @queryToRun1= 'Total Rows In Destination Table After Delete: ' + CAST(@tmpCount AS varchar(20))
										EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun1, @raiseErrorAsPrint = 1, @messagRootLevel = @executionLevel, @messageTreelevel = 2, @stopExecution=0

										EXEC [dbo].[usp_logPrintMessage] @customMessage = 'Delete Data from Destination - Stop', @raiseErrorAsPrint = 1, @messagRootLevel = @executionLevel, @messageTreelevel = 1, @stopExecution=0
									end
								
								---------------------------------------------------------------------------------------------------------
								IF @flgActions & 1 = 1
									begin
										EXEC [dbo].[usp_logPrintMessage] @customMessage = 'Copy Data from Source to Destination - Start', @raiseErrorAsPrint = 1, @messagRootLevel = @executionLevel, @messageTreelevel = 1, @stopExecution=0

										--construiect scriptul de import date			
										SET @queryToRun='INSERT INTO [' + @destinationDB + '].[' + @schemaNameDestination + '].[' + @tableNameDestination + '] ('
										DECLARE crsColumnsMixed CURSOR LOCAL FAST_FORWARD FOR	SELECT [ColumnSource], [ColumnDestination] 
																								FROM #tmpTableColumnsMixed
										OPEN crsColumnsMixed
										FETCH NEXT FROM crsColumnsMixed INTO @columnSource, @columnDestination
										WHILE @@FETCH_STATUS=0
											begin
												SET @queryToRun=@queryToRun +'[' + @columnDestination + '],' 			
												FETCH NEXT FROM crsColumnsMixed INTO @columnSource, @columnDestination
											end
										CLOSE crsColumnsMixed
										DEALLOCATE crsColumnsMixed
				
										SET @queryToRun=SUBSTRING(@queryToRun,1,LEN(@queryToRun)-1) + ') SELECT '
										--------------------------------------------------------------------------------------------------------
		
										DECLARE crsColumnsMixed CURSOR LOCAL FAST_FORWARD FOR	SELECT [ColumnSource], [ColumnDestination] 
																								FROM #tmpTableColumnsMixed
										OPEN crsColumnsMixed
										FETCH NEXT FROM crsColumnsMixed INTO @columnSource, @columnDestination
										WHILE @@FETCH_STATUS=0
											begin
												SET @queryToRun=@queryToRun + '[' + @columnSource + '],' 			
												FETCH NEXT FROM crsColumnsMixed INTO @columnSource, @columnDestination
											end
										CLOSE crsColumnsMixed
										DEALLOCATE crsColumnsMixed
										SET @queryToRun=SUBSTRING(@queryToRun,1,LEN(@queryToRun)-1) + ' FROM [' + @sourceServerName + '].[' + @sourceDB + '].[' + @schemaNameSource + '].[' + @tableNameSource + ']'
		
										---------------------------------------------------------------------------------------------------------
										--detectie identity_insert
										SET @queryToRun1='SELECT count(*) 
														FROM 
														(	SELECT [id] FROM [' + @destinationDB + '].[dbo].[syscolumns] 
															WHERE [AutoVal] IS NOT NULL AND [id] IN (	SELECT so.[id] 
																										FROM [' + @destinationDB + '].[dbo].[sysobjects] so
																										INNER JOIN [' + @destinationDB + '].[dbo].[sysusers] su ON so.[uid] = su.[uid]
																										WHERE so.[name]=''' + @tableNameDestination + '''
																												AND su.[name]=''' + @schemaNameDestination + '''
																									)
															UNION ALL
															SELECT [object_id] FROM [' + @destinationDB + '].[sys].[columns] 
															WHERE [is_identity]=1 AND [object_id] IN (	SELECT so.[id] 
																										FROM [' + @destinationDB + '].[dbo].[sysobjects] so
																										INNER JOIN [' + @destinationDB + '].[dbo].[sysusers] su ON so.[uid] = su.[uid]
																										WHERE so.[name]=''' + @tableNameDestination + '''
																												AND su.[name]=''' + @schemaNameDestination + '''
																									)
														)X'
										SET @queryToRun1 = [dbo].[ufn_formatSQLQueryForLinkedServer](@destinationServerName, @queryToRun1)
										IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun1, @raiseErrorAsPrint = 0, @messagRootLevel = @executionLevel, @messageTreelevel = 0, @stopExecution=01
				
										TRUNCATE TABLE #tmpCount
										INSERT	INTO #tmpCount ([result])
												EXEC (@queryToRun1)
				
										SET @tmpCount=null
										SET @queryToRun1=null
										SELECT @tmpCount=[result] FROM #tmpCount

										IF ISNULL(@tmpCount, 0)>0
											SET @queryToRun1='SET IDENTITY_INSERT [' + @destinationDB + '].[' + @schemaNameDestination + '].[' + @tableNameDestination + '] ON'
										--------------------------------------------------------------------------------------------------------
			
										--in @queryToRun am construit scriptul de insert: INSERT
										--SET IDENTITY_INSERT ON / INSERT / SET IDENTITY_INSERT OFF
										IF ISNULL(@queryToRun1, '')<>''
											SET @queryToRun=@queryToRun1 + char(13) + @queryToRun + char(13) + REPLACE(@queryToRun1, ' ON', ' OFF')

										--------------------------------------------------------------------------------------------------------
										SET @nestExecutionLevel=@executionLevel+1
										EXEC @tmpCount = [dbo].[usp_tableGetRowCount]	@sqlServerName			= @destinationServerName,
																						@databaseName			= @destinationDB,
																						@schemaName				= @schemaNameDestination,
																						@tableName				= @tableNameDestination,
																						@executionLevel			= @nestExecutionLevel,
																						@debugMode				= @debugMode

										SET @queryToRun1= 'Total Rows In Destination Table Before Insert: ' + CAST(@tmpCount AS varchar(20))
										EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun1, @raiseErrorAsPrint = 1, @messagRootLevel = @executionLevel, @messageTreelevel = 2, @stopExecution=0
		
										--------------------------------------------------------------------------------------------------------
										SET @nestExecutionLevel=@executionLevel+1
										EXEC @tmpCount = [dbo].[usp_tableGetRowCount]	@sqlServerName			= @sourceServerName,
																						@databaseName			= @sourceDB,
																						@schemaName				= @schemaNameSource,
																						@tableName				= @tableNameSource,
																						@executionLevel			= @nestExecutionLevel,
																						@debugMode				= @debugMode

										SET @queryToRun1= 'Total Rows In Source Table To Be Copied In Destination: ' + CAST(@tmpCount AS varchar(20))
										EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun1, @raiseErrorAsPrint = 1, @messagRootLevel = @executionLevel, @messageTreelevel = 2, @stopExecution=0
										--------------------------------------------------------------------------------------------------------
				
										IF @debugMode=1	EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = @executionLevel, @messageTreelevel = 0, @stopExecution=0

										SET @queryToRun1= 'Inserting records... '
										EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun1, @raiseErrorAsPrint = 1, @messagRootLevel = @executionLevel, @messageTreelevel = 2, @stopExecution=0

										EXEC @tmpServerDestination @queryToRun
										SET @ReturnValue=@@ERROR
										SET @queryToRun='Error Returned: ' + CAST(@ReturnValue AS varchar)
										EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 1, @messagRootLevel = @executionLevel, @messageTreelevel = 3, @stopExecution=0

										--------------------------------------------------------------------------------------------------------
										--checkident
										SET @nestExecutionLevel = @executionLevel + 1
										EXEC [dbo].[usp_mpDatabaseConsistencyCheck]	@SQLServerName			= @destinationServerName,
																					@DBName					= @destinationDB,
																					@TableSchema			= @schemaNameDestination,
																					@TableName				= @tableNameDestination,
																					@flgActions				= 32,
																					@flgOptions				= DEFAULT,
																					@executionLevel			= @nestExecutionLevel,
																					@debugMode				= @debugMode

										--update usage
										EXEC [dbo].[usp_mpDatabaseConsistencyCheck]	@SQLServerName			= @destinationServerName,
																					@DBName					= @destinationDB,
																					@TableSchema			= @schemaNameDestination,
																					@TableName				= @tableNameDestination,
																					@flgActions				= 64,
																					@flgOptions				= DEFAULT,
																					@executionLevel			= @nestExecutionLevel,
																					@debugMode				= @debugMode

		
										--------------------------------------------------------------------------------------------------------
										SET @nestExecutionLevel=@executionLevel+1
										EXEC @tmpCount = [dbo].[usp_tableGetRowCount]	@sqlServerName			= @destinationServerName,
																						@databaseName			= @destinationDB,
																						@schemaName				= @schemaNameDestination,
																						@tableName				= @tableNameDestination,
																						@executionLevel			= @nestExecutionLevel,
																						@debugMode				= @debugMode

										SET @queryToRun= 'Total Rows In Destination Table After Insert: ' + CAST(@tmpCount AS varchar(20))
										EXEC [dbo].[usp_logPrintMessage] @customMessage = @queryToRun, @raiseErrorAsPrint = 0, @messagRootLevel = @executionLevel, @messageTreelevel = 2, @stopExecution=0

										--------------------------------------------------------------------------------------------------------
										EXEC [dbo].[usp_logPrintMessage] @customMessage = 'Copy Data from Source to Destination - Stop', @raiseErrorAsPrint = 1, @messagRootLevel = @executionLevel, @messageTreelevel = 1, @stopExecution=0
										--------------------------------------------------------------------------------------------------------
									end

								---------------------------------------------------------------------------------------------------------
								--rebuild table non-clustered indexes
								---------------------------------------------------------------------------------------------------------
								IF @flgOptions & 8 = 8
									begin
										SET @nestExecutionLevel = @executionLevel + 1
										EXEC [dbo].[usp_mpAlterTableIndexes]	@sqlServerName				= @destinationServerName,
																				@dbName						= @destinationDB,
																				@tableSchema				= @schemaNameDestination,
																				@tableName					= @tableNameDestination,
																				@indexName					= '%',
																				@indexID					= NULL,
																				@partitionNumber			= 1,
																				@flgAction					= 1,
																				@flgOptions					= DEFAULT,
																				@maxDOP						= 1,
																				@executionLevel				= @nestExecutionLevel, 
																				@affectedDependentObjects	= @affectedDependentObjects OUT,
																				@debugMode					= @debugMode
									end

								---------------------------------------------------------------------------------------------------------
								--enable table constraints
								---------------------------------------------------------------------------------------------------------
								IF @flgOptions & 16 = 16
									begin
										SET @nestExecutionLevel = @executionLevel + 1
										SET @flgOptionsNested = 3 + (@flgOptions & 2048)
	
										--64  - When enabling foreign key constraints, do no check values. Default behaviour is to enabled foreign key constraint with check option
										IF @flgOptions & 64 = 64
											SET @flgOptionsNested = @flgOptionsNested + 4		-- Enable constraints with NOCHECK. Default is to enable constraints using CHECK option

										EXEC [dbo].[usp_mpAlterTableForeignKeys]	@sqlServerName		= @destinationServerName ,
																					@dbName				= @destinationDB,
																					@tableSchema		= @schemaNameDestination, 
																					@tableName			= @tableNameDestination,
																					@constraintName		= '%',
																					@flgAction			= 1,
																					@flgOptions			= @flgOptionsNested,
																					@executionLevel		= @nestExecutionLevel, 
																					@debugMode			= @debugMode
									end

								---------------------------------------------------------------------------------------------------------
								--enable table triggers
								---------------------------------------------------------------------------------------------------------
								IF @flgOptions & 8192 = 8192
									begin
										SET @nestExecutionLevel = @executionLevel + 1
										EXEC [dbo].[usp_mpAlterTableTriggers]		@sqlServerName		= @destinationServerName,
																					@dbName				= @destinationDB,
																					@tableSchema		= @schemaNameDestination, 
																					@tableName			= @tableNameDestination,
																					@triggerName		= '%',
																					@flgAction			= 1,
																					@flgOptions			= @flgOptions,
																					@executionLevel		= @nestExecutionLevel, 
																					@debugMode			= @debugMode
									end			
							end
						---------------------------------------------------------------------------------------------------------
						FETCH NEXT FROM crsDBMixed INTO @schemaNameSource, @tableNameSource, @schemaNameDestination, @tableNameDestination
					end
				CLOSE crsDBMixed
				DEALLOCATE crsDBMixed
			end

		-----------------------------------------------------------------------------------------------------------------------------------------
		--sters tabelele temporare create
		IF object_id('#tmpDBSource') IS NOT NULL DROP TABLE #tmpDBSource
		IF object_id('#tmpDBDestination') IS NOT NULL DROP TABLE #tmpDBDestination
		IF object_id('#tmpDBMixed') IS NOT NULL DROP TABLE #tmpDBMixed
		IF object_id('#tmpTableColumnsSource') IS NOT NULL DROP TABLE #tmpTableColumnsSource
		IF object_id('#tmpTableColumnsDestination') IS NOT NULL DROP TABLE #tmpTableColumnsDestination
		IF object_id('#tmpTableColumnsMixed') IS NOT NULL DROP TABLE #tmpTableColumnsMixed
		IF object_id('#tmpCount') IS NOT NULL DROP TABLE #tmpCount
END TRY

BEGIN CATCH
DECLARE 
        @ErrorMessage    NVARCHAR(4000),
        @ErrorNumber     INT,
        @ErrorSeverity   INT,
        @ErrorState      INT,
        @ErrorLine       INT,
        @ErrorProcedure  NVARCHAR(200);
    -- Assign variables to error-handling functions that 
    -- capture information for RAISERROR.
	SET @ReturnValue = -1

    SELECT 
        @ErrorNumber = ERROR_NUMBER(),
        @ErrorSeverity = ERROR_SEVERITY(),
        @ErrorState = CASE WHEN ERROR_STATE() BETWEEN 1 AND 127 THEN ERROR_STATE() ELSE 1 END ,
        @ErrorLine = ERROR_LINE(),
        @ErrorProcedure = ISNULL(ERROR_PROCEDURE(), '-');
	-- Building the message string that will contain original
    -- error information.
    SELECT @ErrorMessage = 
        N'Error %d, Level %d, State %d, Procedure %s, Line %d, ' + 
            'Message: '+ ERROR_MESSAGE();
    -- Raise an error: msg_str parameter of RAISERROR will contain
    -- the original error information.
    RAISERROR 
        (
        @ErrorMessage, 
        @ErrorSeverity, 
        @ErrorState,               
        @ErrorNumber,    -- parameter: original error number.
        @ErrorSeverity,  -- parameter: original error severity.
        @ErrorState,     -- parameter: original error state.
        @ErrorProcedure, -- parameter: original error procedure name.
        @ErrorLine       -- parameter: original error line number.
        );

        -- Test XACT_STATE:
        -- If 1, the transaction is committable.
        -- If -1, the transaction is uncommittable and should 
        --     be rolled back.
        -- XACT_STATE = 0 means that there is no transaction and
        --     a COMMIT or ROLLBACK would generate an error.

    -- Test if the transaction is uncommittable.
    IF (XACT_STATE()) = -1
    BEGIN
        PRINT
            N'The transaction is in an uncommittable state.' +
            'Rolling back transaction.'
        ROLLBACK TRANSACTION 
   END;

END CATCH

RETURN @ReturnValue
GO
