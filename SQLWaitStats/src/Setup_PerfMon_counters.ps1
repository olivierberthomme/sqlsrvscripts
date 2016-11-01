#########################################################################################################
# Powershell script to setup PerfMon counter for SQL Server performance analysis
#
# Usage : Execute script from Powershell command line
#
# Run : C:\Setup_PerfMon_counters.ps1
#
#########################################################################################################
# History :
#  - 0.1 - 31/10/2016 : Creation

## Import functions
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
. "$scriptPath\Functions_MSSQL.ps1"

#Perfmon DataCollector Name
$cntrname = "PerfMon_SQL_counters"

Pop-Location
$Instances = (get-itemproperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server').InstalledInstances

$OS_Counters = "
\PhysicalDisk(*)\% Disk Time
\PhysicalDisk(*)\Avg. Disk Queue Length
\PhysicalDisk(*)\Avg. Disk sec/Transfert
\PhysicalDisk(*)\Disk Read Bytes/sec
\PhysicalDisk(*)\Disk Write Bytes/sec

\Memory\Available MBytes
\Memory\Free & Zero Page List Bytes
\Memory\Standby Cache Normal Priority Bytes
\Memory\Modified Page List Bytes
\Paging File(_Total)\% Usage

\Processor(_Total)\% Privileged Time
\Processor(_Total)\% Processor Time
\Processor(_Total)\Interrupts/sec
\System\Processor Queue Length
"
Set-Content $pwd\$cntrname.txt $OS_Counters

## Loop on all SQL instances
foreach ($AnInstanceName in $Instances)
{
            $SQL_Counters = "
\MSSQL`$<INSTANCE>:Access Methods\Full Scans/sec 
\MSSQL`$<INSTANCE>:Access Methods\Index Searches/sec
\MSSQL`$<INSTANCE>:Access Methods\Page Splits/sec
\MSSQL`$<INSTANCE>:Locks\Lock Requests/sec
\MSSQL`$<INSTANCE>:Locks\Lock Waits/sec

\MSSQL`$<INSTANCE>:Buffer Manager\Page life expectancy
\MSSQL`$<INSTANCE>:Buffer Manager\Buffer cache hit ratio
\MSSQL`$<INSTANCE>:Buffer Manager\Page lookups/sec

\MSSQL`$<INSTANCE>:Databases(*)\Transactions/sec
\MSSQL`$<INSTANCE>:General Statistics\Logins/sec
\MSSQL`$<INSTANCE>:General Statistics\Active Temp Tables

\MSSQL`$<INSTANCE>:Memory Manager\Memory Grants Pending
\MSSQL`$<INSTANCE>:Memory Manager\SQL Cache Memory (KB)
\MSSQL`$<INSTANCE>:Memory Manager\Free Memory (KB)
\MSSQL`$<INSTANCE>:Memory Manager\Target Server Memory (KB)
\MSSQL`$<INSTANCE>:Memory Manager\Total Server Memory (KB)

\MSSQL`$<INSTANCE>:SQL Statistics\Batch Requests/sec
\MSSQL`$<INSTANCE>:SQL Statistics\SQL Compilations/sec
\MSSQL`$<INSTANCE>:SQL Statistics\SQL Re-Compilations/sec"
            $SQL_Counters | % {$_ -replace "<INSTANCE>", $AnInstanceName} | Add-Content $pwd\$cntrname.txt
}

# Create the Perfmon DataCollector
Write-Output "Metric listed into $pwd\$cntrname.txt"
Write-Output "Metric statistics written into : [$AnInstanceName].[msdb]"
$strCMD = "C:\Windows\System32\logman.exe create counter $cntrname -si 00:00:01 -cf $pwd\$cntrname.txt -f sql -v mmddhhmm -o $cntrname!log1 -rf 168:00:00"

# Confirm before DataCollector creation
Write-Output "Proceed ?"
Write-Output " yes `n no`n(default:no)" 
$Ans = Read-Host 

if ($Ans -eq "yes"){
            # Drop DataCollector if already exists
            try{
                        $DataCollectorSet = new-object -COM Pla.DataCollectorSet
                        Write-Output $DataCollectorSet.Query($cntrname,"localhost")
                        while ($($datacollectorset.Query($cntrname,"localhost")).name -eq $cntrname){
                                   $datacollectorset.stop($false)
                                   Write-Output "stop"
                                   $datacollectorset.delete()
                                   Write-Output "delete"
                                   Start-Sleep -s 2
                        }
            } catch {
                        Write-Output "DataCollector cleanup"
            }
            
            #Create the connection to database (store metric values)
            if ($(Get-OdbcDsn | where {$_.name -eq $cntrname}).size -eq 0) {
                        Add-OdbcDsn -Name $cntrname -DriverName "SQL Server" -DsnType "System" -SetPropertyValue @("Server=localhost\$AnInstanceName", "Trusted_Connection=Yes", "Database=msdb")
            }
            
            # Create the DataCollector
            #Write-Output $strCMD
            Invoke-Expression $strCMD
            
            #Start the DataCollector
            try{
                        $DataCollectorSet = new-object -COM Pla.DataCollectorSet 
                        $datacollectorset.Query($cntrname,"localhost")
                        $datacollectorset.start($false)
            }catch {
                        Write-Output "DataCollector not started..."
            }
}

exit 0

*********************************************************************************************
This email and any files transmitted with it, including replies and forwarded copies (which may contain alterations) subsequently transmitted from the Company, are confidential and solely for the use of the intended recipient. It may contain material protected by attorney-client privilege. The contents do not represent the opinion of Rolex SA except to the extent that it relates to their official business. If you are not the intended recipient or the person responsible for delivering to the intended recipient, be advised that you have received this email in error and that any use is strictly prohibited. If you are not the intended recipient, please advise the sender by return e-mail, then delete this message and any attachments. Rolex SA.
*********************************************************************************************   
