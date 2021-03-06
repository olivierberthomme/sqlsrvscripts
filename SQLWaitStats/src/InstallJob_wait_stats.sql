/*********************************************/
/*  Job creation - gather wait statistics    */
/*      Version 1.1                          */
/*                                           */
/*                                           */
/* History : Job creation                    */
/*           Typo correction                 */
/*           Added comments                  */
/*           GROUP BY added while insert     */
/*           Case sensitive compliant		 */
/*********************************************/

USE [msdb]
GO

/* Drop job if already exists */
declare @exec_text VARCHAR(7000);
set @exec_text =
    N'
USE [msdb]
DECLARE @ReturnNumber INT

select @ReturnNumber = (select count(*) from msdb.dbo.sysjobs_view where name = ''msdb_wait_stats'') ;
IF ( @ReturnNumber <> 0 )
BEGIN
    EXEC sp_delete_job
        @job_name = N''msdb_wait_stats'' ;
END;
';
execute(@exec_text);


/* Create category_name */
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Performance audit]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Performance audit]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

/* Job creation */
DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'msdb_wait_stats',
        @enabled=1,
        @notify_level_eventlog=0,
        @notify_level_email=0,
        @notify_level_netsend=0,
        @notify_level_page=0,
        @delete_level=0,
        @description=N'No description available.',
        @category_name=N'[Performance audit]',
        @owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

/* Unique step creation */
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Gather wait_stats',
        @step_id=1,
        @cmdexec_success_code=0,
        @on_success_action=1,
        @on_success_step_id=0,
        @on_fail_action=2,
        @on_fail_step_id=0,
        @retry_attempts=0,
        @retry_interval=0,
        @os_run_priority=0, @subsystem=N'TSQL',
        @command=N'
USE msdb
GO

IF NOT EXISTS (select * from sys.schemas where name = ''monitoring'')
BEGIN
    declare @exec_text VARCHAR(7000);

    set @exec_text = N''create SCHEMA monitoring;'';
    execute(@exec_text);
END;
GO

IF NOT EXISTS (SELECT * FROM [msdb].[INFORMATION_SCHEMA].[TABLES] WHERE TABLE_SCHEMA = ''monitoring'' AND  TABLE_NAME = ''wait_stats'')
BEGIN
CREATE TABLE [msdb].[monitoring].[wait_stats]
    (
    date datetime NOT NULL,
    server_name nvarchar(80) NOT NULL,
    wait_type nvarchar(50) NOT NULL,
    wait_s DECIMAL (16, 2) NULL,
    resource_s DECIMAL (16, 2) NULL,
    signal_s DECIMAL (16, 2) NULL,
    waitcount DECIMAL (16, 2) NULL,
    percentage DECIMAL (5, 2) NULL,
    avgwait_s DECIMAL (16, 4),
    avgres_s DECIMAL (16, 4),
    avgsig_s DECIMAL (16, 4),
    CONSTRAINT pk_wait_stats PRIMARY KEY (date,server_name,wait_type)
    ) ;
END;

DECLARE @actual_date    DATETIME;
SET  @actual_date     = GETDATE() ;

WITH [Waits] AS
    (SELECT
        [wait_type],
        [wait_time_ms] / 1000.0 AS [WaitS],
        ([wait_time_ms] - [signal_wait_time_ms]) / 1000.0 AS [ResourceS],
        [signal_wait_time_ms] / 1000.0 AS [SignalS],
        [waiting_tasks_count] AS [WaitCount],
        100.0 * [wait_time_ms] / SUM ([wait_time_ms]) OVER() AS [Percentage],
        ROW_NUMBER() OVER(ORDER BY [wait_time_ms] DESC) AS [RowNum]
    FROM sys.dm_os_wait_stats
    WHERE [wait_type] NOT IN (
        N''BROKER_EVENTHANDLER'',         N''BROKER_RECEIVE_WAITFOR'',
        N''BROKER_TASK_STOP'',            N''BROKER_TO_FLUSH'',
        N''BROKER_TRANSMITTER'',          N''CHECKPOINT_QUEUE'',
        N''CHKPT'',                       N''CLR_AUTO_EVENT'',
        N''CLR_MANUAL_EVENT'',            N''CLR_SEMAPHORE'',
        N''DBMIRROR_DBM_EVENT'',          N''DBMIRROR_EVENTS_QUEUE'',
        N''DBMIRROR_WORKER_QUEUE'',       N''DBMIRRORING_CMD'',
        N''DIRTY_PAGE_POLL'',             N''DISPATCHER_QUEUE_SEMAPHORE'',
        N''EXECSYNC'',                    N''FSAGENT'',
        N''FT_IFTS_SCHEDULER_IDLE_WAIT'', N''FT_IFTSHC_MUTEX'',
        N''HADR_CLUSAPI_CALL'',           N''HADR_FILESTREAM_IOMGR_IOCOMPLETION'',
        N''HADR_LOGCAPTURE_WAIT'',        N''HADR_NOTIFICATION_DEQUEUE'',
        N''HADR_TIMER_TASK'',             N''HADR_WORK_QUEUE'',
        N''KSOURCE_WAKEUP'',              N''LAZYWRITER_SLEEP'',
        N''LOGMGR_QUEUE'',                N''ONDEMAND_TASK_QUEUE'',
        N''PWAIT_ALL_COMPONENTS_INITIALIZED'',
        N''QDS_PERSIST_TASK_MAIN_LOOP_SLEEP'',
        N''QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP'',
        N''REQUEST_FOR_DEADLOCK_SEARCH'', N''RESOURCE_QUEUE'',
        N''SERVER_IDLE_CHECK'',           N''SLEEP_BPOOL_FLUSH'',
        N''SLEEP_DBSTARTUP'',             N''SLEEP_DCOMSTARTUP'',
        N''SLEEP_MASTERDBREADY'',         N''SLEEP_MASTERMDREADY'',
        N''SLEEP_MASTERUPGRADED'',        N''SLEEP_MSDBSTARTUP'',
        N''SLEEP_SYSTEMTASK'',            N''SLEEP_TASK'',
        N''SLEEP_TEMPDBSTARTUP'',         N''SNI_HTTP_ACCEPT'',
        N''SP_SERVER_DIAGNOSTICS_SLEEP'', N''SQLTRACE_BUFFER_FLUSH'',
        N''SQLTRACE_INCREMENTAL_FLUSH_SLEEP'',
        N''SQLTRACE_WAIT_ENTRIES'',       N''WAIT_FOR_RESULTS'',
        N''WAITFOR'',                     N''WAITFOR_TASKSHUTDOWN'',
        N''WAIT_XTP_HOST_WAIT'',          N''WAIT_XTP_OFFLINE_CKPT_NEW_LOG'',
        N''WAIT_XTP_CKPT_CLOSE'',         N''XE_DISPATCHER_JOIN'',
        N''XE_DISPATCHER_WAIT'',          N''XE_TIMER_EVENT'')
    ),
[wait_statistics] as
    (SELECT
        [W1].[wait_type] AS [WaitType],
        CAST ([W1].[WaitS] AS DECIMAL (16, 2)) AS [wait_s],
        CAST ([W1].[ResourceS] AS DECIMAL (16, 2)) AS [resource_s],
        CAST ([W1].[SignalS] AS DECIMAL (16, 2)) AS [signal_s],
        [W1].[WaitCount] AS [waitcount],
        CAST ([W1].[Percentage] AS DECIMAL (5, 2)) AS [percentage],
        CAST (([W1].[WaitS] / [W1].[WaitCount]) AS DECIMAL (16, 4)) AS [avgwait_s],
        CAST (([W1].[ResourceS] / [W1].[WaitCount]) AS DECIMAL (16, 4)) AS [avgres_s],
        CAST (([W1].[SignalS] / [W1].[WaitCount]) AS DECIMAL (16, 4)) AS [avgsig_s]
    FROM [Waits] AS [W1]
    INNER JOIN [Waits] AS [W2]
        ON [W2].[RowNum] <= [W1].[RowNum]
    GROUP BY [W1].[RowNum], [W1].[wait_type], [W1].[WaitS],
        [W1].[ResourceS], [W1].[SignalS], [W1].[WaitCount], [W1].[Percentage]
    HAVING SUM ([W2].[Percentage]) - [W1].[Percentage] < 95
)
insert into [msdb].[monitoring].wait_stats
([date],[server_name],[wait_type],[wait_s],[resource_s],[signal_s],[waitcount],[percentage],[avgwait_s],[avgres_s],[avgsig_s])
select @actual_date,@@servername,[WaitType],max([wait_s]) as [wait_s],max([resource_s]) as [resource_s],max([signal_s]) as [signal_s],max([waitcount]) as [waitcount],max([percentage]) as [percentage],max([avgwait_s]) as [avgwait_s],max([avgres_s]) as [avgres_s],max([avgsig_s]) as [avgsig_s]
FROM [wait_statistics]
GROUP BY [WaitType]
;


IF ( DAY (DATEADD(hour,1,@actual_date)) != DAY(@actual_date))
BEGIN
    delete from [msdb].[monitoring].[wait_stats] where [date] < @actual_date - 60;
END;
',
        @database_name=N'msdb',
        @flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Hourly',
        @enabled=1,
        @freq_type=4,
        @freq_interval=1,
        @freq_subday_type=8,
        @freq_subday_interval=1,
        @freq_relative_interval=0,
        @freq_recurrence_factor=0,
        @active_start_date=20140408,
        @active_end_date=99991231,
        @active_start_time=0,
        @active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO


