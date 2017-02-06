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
#  - 0.2 - 06/12/2016 : Ask for MS SQL Instance destination
#  - 0.3 - 19/12/2016 : Changes on DSN creation
#  - 0.4 - 05/02/2017 : Add display on collected metrics + Change collect frequency to 15s + Debug for standard instance

## Import functions
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")){
    Write-Output "Must execute script with Administrator rights"
    exit -1
}

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

\Network Interface(*)\Bytes Received/sec
\Network Interface(*)\Bytes Sent/sec
"
Set-Content $pwd\$cntrname.txt $OS_Counters

## Loop on all SQL instances
foreach ($AnInstanceName in $Instances)
{
            if ($($AnInstanceName).ToString() -eq "MSSQLSERVER"){
                        $AnInstanceName="SQLServer"
            }else{
                        $AnInstanceName="MSSQL`$"+$AnInstanceName
            }
    $SQL_Counters = "
\<INSTANCE>:Access Methods\Full Scans/sec
\<INSTANCE>:Access Methods\Index Searches/sec
\<INSTANCE>:Access Methods\Page Splits/sec
\<INSTANCE>:Locks\Lock Requests/sec
\<INSTANCE>:Locks\Lock Waits/sec

\<INSTANCE>:Buffer Manager\Page life expectancy
\<INSTANCE>:Buffer Manager\Buffer cache hit ratio
\<INSTANCE>:Buffer Manager\Page lookups/sec

\<INSTANCE>:Databases(*)\Transactions/sec
\<INSTANCE>:General Statistics\Logins/sec
\<INSTANCE>:General Statistics\Active Temp Tables

\<INSTANCE>:Memory Manager\Memory Grants Pending
\<INSTANCE>:Memory Manager\SQL Cache Memory (KB)
\<INSTANCE>:Memory Manager\Free Memory (KB)
\<INSTANCE>:Memory Manager\Target Server Memory (KB)
\<INSTANCE>:Memory Manager\Total Server Memory (KB)

\<INSTANCE>:SQL Statistics\Batch Requests/sec
\<INSTANCE>:SQL Statistics\SQL Compilations/sec
\<INSTANCE>:SQL Statistics\SQL Re-Compilations/sec"
            $SQL_Counters | % {$_ -replace "<INSTANCE>", $AnInstanceName} | Add-Content $pwd\$cntrname.txt
}

# Create the Perfmon DataCollector
Write-Output "Metric listed into $pwd\$cntrname.txt"
$strCMD = "C:\Windows\System32\logman.exe create counter $cntrname -si 00:00:15 -cf $pwd\$cntrname.txt -f sql -v mmddhhmm -o $cntrname!log1 -rf 168:00:00"

# Confirm before DataCollector creation
Write-Output "Proceed ?"
Write-Output " yes `n no`n(default:no)"
$Ans = Read-Host

if ($Ans -eq "yes"){
                                   $MSSQL_destination = $($Instances[0])
                                   # Select SQL Server instance destination
                                   if ($Instances.count -gt 1){
                                                  $Ans = -1
                                                  $i = 0
                                                  while ($Ans -lt 0 -or $Ans -gt $($i-1)){
                                                  $i=0
                                                  Write-Output "Choose the instance hosting the metrics"
                                                  foreach ($AnInstanceName in $Instances)
                                                  { Write-Output "$($i): $AnInstanceName" ; $i++}
                                                  $Ans = Read-Host
                                                  }
                                                  $MSSQL_destination=$($Instances[$Ans])
                                   }else{
                                                  $MSSQL_destination=$($Instances[0])
                                   }
                                   Write-Output "Metric statistics written into : [$MSSQL_destination].[msdb]"

            # Drop DataCollector if already exists
            try{
                        $DataCollectorSet = new-object -COM Pla.DataCollectorSet
                        $($datacollectorset.Query($cntrname,$null))
                        $datacollectorset.stop($false)
                        Write-Output "Stop DataCollectorSet"
                        $datacollectorset.delete()
                        Write-Output "Delete DataCollectorSet"
                        Start-Sleep -s 2
            } catch {
                        Write-Output "DataCollector cleanup not done !"
            }

           #Create the connection to database (store metric values)
           if ($(get-odbcdsn | where name -eq $cntrname) ){
                       Write-Output "DSN already exists"
           } else {
                if($MSSQL_destination -eq "MSSQLSERVER"){
                      Add-OdbcDsn -Name $cntrname -DriverName "SQL Server" -DsnType "System" -SetPropertyValue @("Server=localhost", "Trusted_Connection=Yes", "Database=msdb")
                }else{
                      Add-OdbcDsn -Name $cntrname -DriverName "SQL Server" -DsnType "System" -SetPropertyValue @("Server=localhost\$MSSQL_destination", "Trusted_Connection=Yes", "Database=msdb")
                }
           }

           # Create the DataCollector
           #Write-Output $strCMD
           Invoke-Expression $strCMD

           #Start the DataCollector
           try{
                       $DataCollectorSet = new-object -COM Pla.DataCollectorSet
                       $datacollectorset.Query($cntrname,$null)
                       $datacollectorset.start($false)
                                                              Write-Output "DataCollector started..."
           }catch {
                       Write-Output "DataCollector not started..."
           }
                           Write-Output "Wait a little then check the saved metric values in SQL Server..."
                           Start-Sleep -s 30

                           # Display metrics collected
                           if($MSSQL_destination -eq "MSSQLSERVER"){
                Invoke-Sqlcmd -Query "SELECT DISTINCT [ObjectName]+' '+ISNULL([CounterName],'')+' '+ISNULL([InstanceName],'') as CounterName FROM [msdb].[dbo].[CounterDetails] order by 1;" -ServerInstance "localhost"
                           }else{
                                               Invoke-Sqlcmd -Query "SELECT DISTINCT [ObjectName]+' '+ISNULL([CounterName],'')+' '+ISNULL([InstanceName],'') as CounterName FROM [msdb].[dbo].[CounterDetails] order by 1;" -ServerInstance "localhost\$MSSQL_destination"
                           }
}

exit 0
