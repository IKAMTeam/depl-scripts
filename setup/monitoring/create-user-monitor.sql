create user monitor identified by monitor;
grant create session to monitor;
grant alter session to monitor;

--privs for hosted DB:
--grant select on dba_scheduler_jobs to monitor;
--grant select on dba_objects to monitor;
--grant select on dba_scheduler_job_run_details to monitor;
--grant select on dba_indexes to monitor;
--grant select on dba_ind_partitions to monitor;
--grant select on gv_$lock to monitor;
--grant select on gv_$session to monitor;
--grant select on gv_$sqlarea to monitor;
--grant select on gv_$sesstat to monitor;
--grant select on gv_$statname to monitor;
--grant select on gv_$parameter to monitor;


--privs for AWS RDS:
--grant select_catalog_role to monitor;
