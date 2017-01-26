WITH sum_wait as (
SELECT SUM(end_sp.wait_s)-sum(start_sp.wait_s) as sum_wait_s
	  , MIN(start_sp.date) as start_date
	  , MAX(end_sp.date) as end_date
from [msdb].[monitoring].[wait_stats] start_sp inner join 
	 [msdb].[monitoring].[wait_stats] end_sp on start_sp.wait_type=end_sp.wait_type
WHERE     CONVERT(nvarchar(MAX), start_sp.date, 120) like '2014-10-27 11:0%'
      and CONVERT(nvarchar(MAX), end_sp.date  , 120) like '2014-10-27 14:0%'
	  and start_sp.wait_type not like 'PREEMPTIVE_%'
	  and end_sp.wait_type not like 'PREEMPTIVE_%'
)
SELECT start_sp.wait_type
      ,SUM(end_sp.wait_s)-ISNULL(SUM(start_sp.wait_s),0) as wait_s
      ,SUM(end_sp.resource_s)-ISNULL(SUM(start_sp.resource_s),0) as resource_s
      ,SUM(end_sp.[signal_s])-ISNULL(SUM(start_sp.[signal_s]),0) assignal_s
      ,SUM(end_sp.[waitcount])-ISNULL(SUM(start_sp.[waitcount]),0) as waitcount
      ,(SUM(end_sp.wait_s)-ISNULL(SUM(start_sp.wait_s),0)) / SUM(sum_wait.sum_wait_s) * 100 as pct
  FROM [msdb].[monitoring].[wait_stats] start_sp  full outer join
	   [msdb].[monitoring].[wait_stats] end_sp on start_sp.wait_type=end_sp.wait_type,
	   sum_wait
WHERE start_sp.date = sum_wait.start_date
      and end_sp.date = sum_wait.end_date
	  and start_sp.wait_type not like 'PREEMPTIVE_%'
	  and end_sp.wait_type not like 'PREEMPTIVE_%'
group by start_sp.wait_type
order by wait_s desc
;
