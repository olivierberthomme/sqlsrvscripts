#########################################################################################################
# Powershell script to check best practice configuration of SQL Server for a SharePoint installation
#
# Usage : Execute script from Powershell command line
# Optional parameter : Instance name hosting Sharepoint databases
# 	> Without parameter, script will check all local instances
#
# Run : C:\CheckList_MSSQL_Shpt.ps1 -instance SHAREPOINT
#
#########################################################################################################
# History :
#  - 0.1 - 15/10/2014 : Creation
#  - 0.2 - 17/10/2014 : Add model + tempdb best practice check
#  - 0.2 - 20/10/2014 : Add checks based on farm size
#  - 0.3 - 23/10/2014 : Add last DB backups check
#  - 0.3 - 24/10/2014 : Minor changes for SQL2008 versions
#  - 0.4 - 18/12/2014 : Skip not available databases (recovering, unavailable ...)
#  - 0.5 - 09/01/2015 : Mount points aware
#  - 0.6 - 29/01/2015 : Checks admin rights ; checks NTFS cluster size on mount points
#  - 0.7 - 18/02/2015 : Debug
#  - 0.7.3 19/02/2015 : Debug
#  - 0.8 - 20/02/2015 : Update connection strings
#  - 0.9e  12/03/2015 : Generate HTML report
#  - 1.0 - 13/03/2015 : Finalize report
#  - 1.1 - 16/03/2015 : Remove HtmlEncode function
#  - 1.2 - 04/05/2015 : Debug for FCI connection
#  - 1.3 - 15/05/2015 : Rename powershell external function file
#########################################################################################################
Param(
    [Parameter(HelpMessage="Instance name to check")]
    [alias("Instance")]
    [String] $Param_Instance_name
)

Write-Host "Starting CheckList_MSSQL_Shpt v1.3"
$HMTL_title = "<h1>Checklist of SQL Server best practices for Sharepoint</h1>"
$HMTL_title+= "`n<i>CheckList_MSSQL_Shpt.ps1 v1.3</i>`n"


## Import functions
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
. "$scriptPath\Functions_MSSQL.ps1"

## Load SQL Server Management Objects (SMO)
loadModule

## Script must be executed with admin privileges
if (!(Test-IsAdmin)){
	throw "Please run this script with admin priviliges"
}

Push-Location
$Instances = (get-itemproperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server').InstalledInstances

$HTML_summary = "`n<ul>"

foreach ($AnInstanceName in $Instances)
{
	if (!${Param_Instance_name} -or  $Param_Instance_name -eq $AnInstanceName){
		Write-Host ""
		Write-Host "`t`tAnalyze instance : $AnInstanceName" -foreground red -background yellow
		Write-Host ""
		$HTML_connection = "`n<h2><a name='$AnInstanceName'>" + $AnInstanceName + "</a></h2>"
		$HTML_summary   += "`n<li><a href='#$AnInstanceName'>" + $AnInstanceName + "<a/></li>"
		
		$connected = $FALSE
		# Basic connection string
        try{
			$connection_string="localhost\$AnInstanceName"
			Write-Host "`t trying connection : localhost\$AnInstanceName..." -NoNewLine
			$SQL_Instance = new-object ('Microsoft.SqlServer.Management.Smo.Server') $connection_string
            Select-Object -ExpandProperty BuildNumber -InputObject $SQL_Instance -ErrorAction Stop
			$connected = $TRUE
        }
        Catch
        {
			$connected = $FALSE
        }
		
		# Connection to a not named instance
		if (! $connected ){
			try{
				if ($AnInstanceName -like "MSSQLSERVER"){
						$connection_string="localhost"
						Write-Host "`n`t trying connection : $connection_string..." -NoNewLine
						$SQL_Instance = new-object ('Microsoft.SqlServer.Management.Smo.Server') $connection_string
						Select-Object -ExpandProperty BuildNumber -InputObject $SQL_Instance -ErrorAction Stop
						$connected = $TRUE
				}
			}
			Catch
			{
				$connected = $FALSE
			}
		}

		# Connection with Shared Memory localhost\instance
		if (! $connected ){
			try{
				$connection_string="lpc:localhost\$AnInstanceName"
				Write-Host "`n`t trying connection : $connection_string..." -NoNewLine
				$SQL_Instance = new-object ('Microsoft.SqlServer.Management.Smo.Server') $connection_string
				Select-Object -ExpandProperty BuildNumber -InputObject $SQL_Instance -ErrorAction Stop
				$connected = $TRUE
			}
			Catch
			{
				$connected = $FALSE
			}

		}

		# Connection with Shared Memory localhost
		if (! $connected ){
			try{
				$connection_string="lpc:localhost"
				Write-Host "`n`t trying connection : $connection_string..." -NoNewLine
				$SQL_Instance = new-object ('Microsoft.SqlServer.Management.Smo.Server') $connection_string
				Select-Object -ExpandProperty BuildNumber -InputObject $SQL_Instance -ErrorAction Stop
				$connected = $TRUE
			}
			Catch
			{
				$connected = $FALSE
			}
		}		
		
		# Connection to cluster instance
		if (! $connected ){
			try{
				$Regedit_FQNInstance = (get-itemproperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL' -ErrorAction Stop).$AnInstanceName
				$Regedit_ClusterName = (get-itemproperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$Regedit_FQNInstance\Cluster" -ErrorAction Stop).ClusterName
				$connection_string=$Regedit_ClusterName
				if (! [string]::IsNullOrWhiteSpace($connection_string)){
					Write-Host "`n`t trying connection : $connection_string..." -NoNewLine
					$SQL_Instance = new-object ('Microsoft.SqlServer.Management.Smo.Server') $connection_string
					Select-Object -ExpandProperty BuildNumber -InputObject $SQL_Instance -ErrorAction Stop
					$connected = $TRUE
				}
			}
			Catch
			{
				$connected = $FALSE
			}
		}

		if (! $connected ){
			Write-Host "`nFailed to connect" -foreground red
			$HTML_connection += "`Failed to connect.</br></br>"
			## Compose HTML portion for the instance :
			$HMTL_instances += $HTML_connection
			continue;
		}else{
			Write-Host "`t Connected" -foreground green
			$HTML_connection += "`nConnection string : " + $connection_string + "</br></br>"
		}
		
		## Instance checks
		$HTML_instance="`n<h3>Instance parameters</h3>"
		$instance_checks = @()
		
		Write-Host "`n> Check : Named instance `t`t" -foreground Gray
		$InstanceName = Select-Object -ExpandProperty InstanceName -InputObject $SQL_Instance -ErrorAction Stop
		if (!($InstanceName -like "MSSQLSERVER") -and !($InstanceName -like ""))					{ Write-Host -foreground green "OK" } else  {Write-Host -foreground red "Failed" }
		Write-Host "Instance Name : $InstanceName`t`t(should not be MSSQLSERVER)"
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "Instance Name"
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value"		-Value $InstanceName
		Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if (!($InstanceName -like "MSSQLSERVER") -and !($InstanceName -like "")) {"OK"} else  {"Failed"})
		Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "Instance name should not be MSSQLSERVER for security reasons"
		$instance_checks += $check
		
		Write-Host "`n> Check default instance collation `t`t" -NoNewLine -foreground Gray
		$Collation = Select-Object -ExpandProperty Collation -InputObject $SQL_Instance
		if ($Collation -like "Latin1_General_CI_AS*" -and $Collation -notLike "*_KI_*" -and $Collation -notLike "*_WI*")		{ Write-Host -foreground green "OK" } else  {Write-Host -foreground red "Failed" }
		Write-Host "Collation : $Collation`t`t(should be Latin1_General_CI_AS_KS_WS)"
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "Collation"
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value"		-Value $Collation
		Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if($Collation -like "Latin1_General_CI_AS*" -and $Collation -notLike "*_KI_*" -and $Collation -notLike "*_WI*") {"OK"} else  {"Failed"})
		Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "Collation should be Latin1_General_CI_AS_KS_WS"
		$instance_checks += $check
		
		Write-Host "`n> Check Max DOP `t`t" -NoNewLine -foreground Gray
		$MaxDOP = $SQL_Instance.Configuration.MaxDegreeOfParallelism.ConfigValue
		if ($MaxDOP -eq 1)		{ Write-Host -foreground green "OK" } else  {Write-Host -foreground red "Failed" }
		Write-Host "SQL Max DOP : $MaxDOP`t`t`t(should be =1)"
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "Max degree of parallelism"
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value"		-Value $MaxDOP
		Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if($MaxDOP -eq 1) {"OK"} else  {"Failed"})
		Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "Sharepoint require to disable parallelism (Max DOP=1)"
		$instance_checks += $check
		
		Write-Host "`n> Check Fill Factor `t`t" -NoNewLine -foreground Gray
		$FillFactor = $SQL_Instance.Configuration.FillFactor.ConfigValue
		if ($FillFactor -eq 80)		{ Write-Host -foreground green "OK" } else  {Write-Host -foreground red "Failed" }
		Write-Host "SQL FillFactor : $FillFactor`t`t`t(should be 80)"
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "Fill Factor"
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value"		-Value $FillFactor
		Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if($FillFactor -eq 80) {"OK"} else  {"Failed"})
		Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "Sharepoint advise a fill factor of 80%"
		$instance_checks += $check
		
		## Network checks
		Write-Host "`n> Check TCP enabled `t`t" -NoNewLine -foreground Gray
		$mc = new-object ('Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer') localhost
		$tcp = $($mc.ServerInstances[$AnInstanceName]).ServerProtocols['Tcp']
		$TCPEnabled = $Tcp.IsEnabled
		if ($TCPEnabled)		{ Write-Host -foreground green "OK" } else  {Write-Host -foreground red "Failed" }
		Write-Host "TCP Enabled : $TCPEnabled`t`t(should be true)"
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "TCP connection"
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value"	 	-Value $TCPEnabled
		Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if($TCPEnabled) {"OK"} else  {"Failed"})
		Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "Connection via TCP should be enabled"
		$instance_checks += $check
		
		# Retrieve all ports configured
		$DynamicPortNum = @()
		$FixedPortNum 	= @()
		foreach ($IPAddress in $($tcp.IPAddresses | Sort-Object name)){
			foreach($prop in $IPAddress.IPAddressProperties){ 
				if ($prop.name -match "TcpPort") 			{ $FixedPortNum += $prop.value}
				if ($prop.name -match "TcpDynamicPorts") 	{ $DynamicPortNum += $prop.value}
			}
		}
		$DynamicPortNum = $DynamicPortNum | Sort-Object | Get-Unique
		$FixedPortNum = $FixedPortNum | Sort-Object | Get-Unique

 		Write-Host "`n> Check Fixed Port Number `t" -NoNewLine -foreground Gray
		if ($FixedPortNum -notcontains "1433")			{ Write-Host -foreground green "OK" } else  {Write-Host -foreground red "Failed" }
		Write-Host "Listener port : $FixedPortNum`t`t(should not be 1433)"
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "Fixed listener port number"
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $([string]$FixedPortNum)
		Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if($FixedPortNum -notcontains "1433") {"OK"} else  {"Failed"})
		Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "Connection on standard port (1433) should not be enabled for security reasons"
		$instance_checks += $check
	
 		Write-Host "`n> Check Dynamic Port Number `t" -NoNewLine -foreground Gray
		if ($DynamicPortNum -notcontains "1433")		{ Write-Host -foreground green "OK" } else  {Write-Host -foreground red "Failed" }
		Write-Host "Listener dynamic port : $DynamicPortNum`t`t(should not be 1433)"
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "Dynamic listener port numbers"
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $([string]$DynamicPortNum)
		Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if($DynamicPortNum -notcontains "1433") {"OK"} else  {"Failed"})
		Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "Connection on standard port (1433) should not be enabled for security reasons"
		$instance_checks += $check
		
		$HTML_instance += $instance_checks | Convertto-HTML -Fragment
		
		#Databases checks		
		# model check
		$HTML_modeldb="`n<h4>model Database</h4>"
		$modeldb_checks = @()
		$modeldb_files = @()
		Write-Host "`n> Check model DB `t" -foreground Gray
		foreach ($database in $SQL_Instance.Databases){
			if ($database.name -eq "model"){
				
				$AutoUpdateStatisticsEnabled  = Select-Object -ExpandProperty AutoUpdateStatisticsEnabled  -InputObject $database
				Write-Host " - model DB AutoUpdateStatistics: $AutoUpdateStatisticsEnabled `t`t" -NoNewLine
				if (!$AutoUpdateStatisticsEnabled)		{ Write-Host -foreground green "OK" } else  {Write-Host -foreground red "Failed" }
				Write-Host "   (AutoUpdateStatistics on model DB should be disabled)`n"
				$check = New-Object -TypeName PSObject
				Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "modelDB AutoUpdateStatistics parameter"
				Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $([string]$AutoUpdateStatisticsEnabled)
				Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if(!$AutoUpdateStatisticsEnabled) {"OK"} else  {"Failed"})
				Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "AutoUpdateStatistics should be disable on modelDB (future databases)"
				$modeldb_checks += $check

				$dataSize = 0
				$data_autogrowth_check = $TRUE
				$fileGroups = $database.FileGroups
				ForEach ($fg in $fileGroups){
					If ($fg) {
						ForEach ($dataFiles in $fg.Files){
							$dataSize += $($dataFiles.size) # in KB
							Write-Host "data file $($dataFiles.ID) size : $($dataFiles.size)KB`t autoGrowth : $($dataFiles.Growth) $($dataFiles.GrowthType)`t`t" -NoNewLine
							if ($($dataFiles.Growth) -ge 512000 -and $($dataFiles.GrowthType) -match "KB")		{ 
								Write-Host -foreground green "OK"
							} else  {
								Write-Host -foreground red "Failed" 
								if ($data_autogrowth_check) { $data_autogrowth_check=$FALSE }
							}
							$file = New-Object -TypeName PSObject
							Add-Member -InputObject $file -Type NoteProperty -Name "Name" 		-Value $([string]$dataFiles.name)
							Add-Member -InputObject $file -Type NoteProperty -Name "Type" 		-Value "Data"
							Add-Member -InputObject $file -Type NoteProperty -Name "Size (KB)" 	-Value $([string]$dataFiles.size)
							Add-Member -InputObject $file -Type NoteProperty -Name "AutoGrowth" -Value $([string]$dataFiles.Growth + [string]$dataFiles.GrowthType)
							$modeldb_files += $file
						}
					}
				}
				Write-Host " - Total model DB data file size: $dataSize KB`t`t" -NoNewLine				
				if ($dataSize -ge 512000)		{ Write-Host -foreground green "OK" } else  {Write-Host -foreground red "Failed" }
				Write-Host "   (model DB data size should be >512MB AutoGrowth should be 512MB)`n"
				$check = New-Object -TypeName PSObject
				Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "modelDB size"
				Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $([string]$dataSize + "KB")
				Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if($dataSize -ge 512000) {"OK"} else  {"Failed"})
				Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "Sum of all modelDB data file size should be greater than 512MB"
				$modeldb_checks += $check
				
				$check = New-Object -TypeName PSObject
				Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "modelDB data file AutoGrowth"
				Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if($data_autogrowth_check) {"OK"} else  {"Failed"})
				Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "modelDB data files should be configured with an 512MB autogrowth"
				$modeldb_checks += $check
				
				$logSize = 0
				$log_autogrowth_check = $TRUE
				ForEach ($logFiles in $database.LogFiles){
					$logSize += $($logFiles.size)
					Write-Host "log  file $($logFiles.ID) size : $($logFiles.size)KB`t autoGrowth : $($logFiles.Growth) $($logFiles.GrowthType)`t`t" -NoNewLine
					if (($($logFiles.Growth) -ge 512000 -and $($logFiles.GrowthType) -match "KB")	-or ($($logFiles.Growth) -ge 100 -and $($logFiles.GrowthType) -match "Percent"))	{
						Write-Host -foreground green "OK" $
					} else  {
						Write-Host -foreground red "Failed" 
						if ($log_autogrowth_check) { $log_autogrowth_check = $FALSE }
					}					
					$file = New-Object -TypeName PSObject
					Add-Member -InputObject $file -Type NoteProperty -Name "Name" 		-Value $([string]$logFiles.name)
					Add-Member -InputObject $file -Type NoteProperty -Name "Type" 		-Value "TransactionLog"
					Add-Member -InputObject $file -Type NoteProperty -Name "Size (KB)" 	-Value $([string]$logFiles.size)
					Add-Member -InputObject $file -Type NoteProperty -Name "AutoGrowth" -Value $([string]$logFiles.Growth + [string]$logFiles.GrowthType)
					$modeldb_files += $file
				}
				
				Write-Host " - Total model DB log  file size: $logSize KB`t`t" -NoNewLine				
				if ($logSize -ge 512000)		{ Write-Host -foreground green "OK" } else  {Write-Host -foreground red "Failed" }
				Write-Host "   (model DB log  size should be >512MB AutoGrowth should be 512MB or 100%)`n"
				$check = New-Object -TypeName PSObject
				Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "modelDB log size"
				Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $([string]$logSize + "KB")
				Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if($logSize -ge 512000) {"OK"} else  {"Failed"})
				Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "modelDB transaction log size should be greater than 512MB"
				$modeldb_checks += $check

				$check = New-Object -TypeName PSObject
				Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "modelDB transaction log AutoGrowth"
				Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if($log_autogrowth_check) {"OK"} else  {"Failed"})
				Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "modelDB transaction log should be configured with an 512M or 100% autogrowth"
				$modeldb_checks += $check
			}
		}
		$HTML_modeldb += $modeldb_checks | Convertto-HTML -Fragment
		$HTML_modeldb += "`nFiles: <a id=`"data_header_$InstanceName`" href=`"javascript:toggle2('model_files_$InstanceName','data_header_$InstanceName');`" >Hide details</a>`n"
		$HTML_modeldb += "<div id=`"model_files_$InstanceName`" style=`"display: block;`">"
		$HTML_modeldb += $modeldb_files | Convertto-HTML -Fragment
		$HTML_modeldb +="`n</div>"
		
		# tempDB check
		$HTML_tempdb="`n<h4>temp Database</h4>"
		$tempdb_checks = @()
		$tempdb_files = @()
		Write-Host "`n> Check TempDB `t" -foreground Gray
		foreach ($database in $SQL_Instance.Databases){
			if ($database.name -eq "tempdb"){
				Write-Host " tempDB Size: $($database.size) `t`t" -NoNewLine
				if ($($database.size) -ge 2048)		{ Write-Host -foreground green "OK" } else  {Write-Host -foreground red "Failed" }
				$check = New-Object -TypeName PSObject
				Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "tempDB size"
				Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $([string]$database.size + "KB")
				Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if($($database.size) -ge 2048) {"OK"} else  {"Failed"})
				Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "tempDB should be bigger or equal 2GB"
				$tempdb_checks += $check
				
				Write-Host " tempDB recovery model : $($database.RecoveryModel) `t" -NoNewLine
				if ($($database.RecoveryModel) -match "Simple")		{ Write-Host -foreground green "OK" } else  {Write-Host -foreground red "Failed" }
				$check = New-Object -TypeName PSObject
				Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "tempDB recovery model"
				Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $([string]$database.RecoveryModel)
				Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if($($database.RecoveryModel) -match "Simple") {"OK"} else  {"Failed"})
				Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "tempDB should be configured in SIMPLE recovery model"
				$tempdb_checks += $check
				
				$data_autogrowth_check 	= $TRUE
				$data_size_check 		= $TRUE
				$fileGroups = $database.FileGroups
				ForEach ($fg in $fileGroups){
					If ($fg) {
						ForEach ($dataFiles in $fg.Files){
							Write-Host " file $($dataFiles.ID) size : $($dataFiles.size) KB`t`t`t" -NoNewLine
							if ($($dataFiles.size) -ge 2097152)		{ 
								Write-Host -foreground green "OK" 
							} else  {
								Write-Host -foreground red "Failed" 
								if ($data_size_check) { $data_size_check = $FALSE }
							}
							Write-Host " file $($dataFiles.ID) autoGrowth : $($dataFiles.Growth) $($dataFiles.GrowthType)`t`t" -NoNewLine
							if ($($dataFiles.Growth) -ge 1048576 -and $($dataFiles.GrowthType) -match "KB")		{ 
								Write-Host -foreground green "OK" 
							} else  {
								Write-Host -foreground red "Failed"
								if ($data_autogrowth_check) { $data_autogrowth_check = $FALSE }
							}
							$file = New-Object -TypeName PSObject
							Add-Member -InputObject $file -Type NoteProperty -Name "Name" 		-Value $([string]$dataFiles.name)
							Add-Member -InputObject $file -Type NoteProperty -Name "Type" 		-Value "Data"
							Add-Member -InputObject $file -Type NoteProperty -Name "Size (KB)" 	-Value $([string]$dataFiles.size)
							Add-Member -InputObject $file -Type NoteProperty -Name "AutoGrowth" -Value $([string]$dataFiles.Growth + [string]$dataFiles.GrowthType)
							$tempdb_files += $file
						}
					}
				}
				Write-Host "tempdb should be recovery model simple, sum of files >2GB and AutoGrowth identical (and >1GB)"
				
				$check = New-Object -TypeName PSObject
				Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "tempdb data files size"
				Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if($data_size_check) {"OK"} else  {"Failed"})
				Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "tempDB should have data file > 2GB"
				$tempdb_checks += $check
				
				$check = New-Object -TypeName PSObject
				Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "tempdb data file AutoGrowth"
				Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if($data_autogrowth_check) {"OK"} else  {"Failed"})
				Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "tempdb data files should be configured with autogrowth >1GB"
				$tempdb_checks += $check
			}
		}
		
		$HTML_tempdb += $tempdb_checks | Convertto-HTML -Fragment
		$HTML_tempdb += "`nFiles: <a id=`"temp_header_$InstanceName`" href=`"javascript:toggle2('tempdb_files_$InstanceName','temp_header_$InstanceName');`" >Hide details</a>`n"
		$HTML_tempdb += "<div id=`"tempdb_files_$InstanceName`" style=`"display: block;`">"
		$HTML_tempdb += $tempdb_files | Convertto-HTML -Fragment
		$HTML_tempdb +="`n</div>"
		
		
		# user databases checks
        Write-Host "`n> Now checking users' databases" -foreground Gray
		$HTML_userdb="`n<h4>User Databases</h4>"
		$user_checks 	= @()
		$user_db 		= @()
		$userdb_collation_ok 	= $TRUE
		$userdb_autostats_ok 	= $TRUE
		$userdb_backups_ok 		= $TRUE
		$NTFS_cluster_ok 		= $TRUE
		if ($SQL_Instance.Databases.count -gt 4) {
				# Generate db objects
				foreach ($database in $SQL_Instance.Databases){
					if ($database.status -NotContains "Normal") 					{ continue }
					if ("master","model","msdb","tempdb" -Contains $database.name) 	{ continue }
					$db = New-Object -TypeName PSObject
					Add-Member -InputObject $db -Type NoteProperty -Name "Name" -Value $database.name
					Add-Member -InputObject $db -Type NoteProperty -Name "Last Log Backup" -Value "-"
					$user_db += $db
				}
				
				if ($user_db.count -ne 0) {
					$DiskDrive4Data = @();
					$DiskDrive4Log  = @();
					
					Write-Host "`n> Check files location `t" -NoNewLine -foreground Gray
					$mountPointList = Get-WmiObject Win32_Volume -Filter "DriveType='3'" -property name | sort-object -property @{Expression={$_.name.length};Descending=$true} | format-table -property name -HideTableHeaders | out-string -stream | % {$_.Trim()}
					
					foreach ($database in $SQL_Instance.Databases){
						if ($database.status -NotContains "Normal") 					{ continue }
						if ("master","model","msdb","tempdb" -Contains $database.name) 	{ continue }
						$fileGroups = $database.FileGroups
						$DBDiskDrive4Data = @();
						$DBDiskDrive4Log  = @();
						ForEach ($fg in $fileGroups){
							If ($fg) {
								ForEach ($dataFiles in $fg.Files){
									$DBDiskDrive4Data += get-mountPoint $mountPointList $dataFiles.FileName
								}
							}
						}
						ForEach ($logFiles in $database.LogFiles){
							$DBDiskDrive4Log += get-mountPoint $mountPointList $logFiles.FileName
						}
						$user_db | where { $_.name -eq $database.name} | Add-Member -Type NoteProperty -Name "Data volume(s)" -Value $([string]$($DBDiskDrive4Data | Sort-Object | Get-Unique))
						$user_db | where { $_.name -eq $database.name} | Add-Member -Type NoteProperty -Name "Log volume(s)"  -Value $([string]$($DBDiskDrive4Log  | Sort-Object | Get-Unique))
						$DiskDrive4Data += $DBDiskDrive4Data
						$DiskDrive4Log  += $DBDiskDrive4Log
					}
					$DiskDrive4Data = $DiskDrive4Data | Sort-Object | Get-Unique
					$DiskDrive4Log  = $DiskDrive4Log  | Sort-Object | Get-Unique
					if ( (![string]::IsNullOrWhiteSpace($DiskDrive4Data)) -and (![string]::IsNullOrWhiteSpace($DiskDrive4Log))){
						if (!(Compare-Object -ReferenceObject $DiskDrive4Log -DifferenceObject $DiskDrive4Data -ExcludeDifferent -IncludeEqual))		{ Write-Host -foreground green "OK" } else  {Write-Host -foreground red "Failed" }
						Write-Host " Data disk drive : "$DiskDrive4Data
						Write-Host " Log  disk drive : "$DiskDrive4Log
						Write-Host "Data and Log files should be on separate drives"
						
						$check = New-Object -TypeName PSObject
						Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "Disk access"
						Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $("Data drive(s):" + [string]$DiskDrive4Data + " - Log drive(s):" + [string]$DiskDrive4Log)
						Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if(!(Compare-Object -ReferenceObject $DiskDrive4Log -DifferenceObject $DiskDrive4Data -ExcludeDifferent -IncludeEqual)) {"OK"} else  {"Failed"})
						Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "Data files and transaction log files should be on separate drives (or separate mount point)"
						$user_checks += $check
					}else{
						Write-Host -foreground red "Failed"
						Write-Host "Cannot retrieve Data and Log disk drive..."
						Write-Host "Data and Log files should be on separate drives"
					}
					
					Write-Host "`n> Check collation" -foreground Gray
					foreach ($database in $SQL_Instance.Databases){
						if ("master","model","msdb","tempdb" -NotContains $database.name){
							Write-Host "DB : $database `t`t" -NoNewLine
							$Collation = Select-Object -ExpandProperty Collation -InputObject $database
							if ($Collation -like "Latin1_General_CI_AS*" -and $Collation -notLike "*_KI_*" -and $Collation -notLike "*_WI*")		{ 
								Write-Host -foreground green "OK" 
							} else  {
								Write-Host -foreground red "Failed"
								if($userdb_collation_ok) {$userdb_collation_ok=$FALSE}
							}						
							$user_db | where { $_.name -eq $database.name} | Add-Member -Type NoteProperty -Name "Collation" -Value $Collation
						}
					}
					Write-Host "Collation : `t`t`t`t(should be Latin1_General_CI_AS_KS_WS)"
					$check = New-Object -TypeName PSObject
					Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "Collations"
					Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if($userdb_collation_ok) {"OK"} else  {"Failed"})
					Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "user databases collation should be Latin1_General_CI_AS_KS_WS"
					$user_checks += $check
					
					Write-Host "`n> Check AutoUpdateStatistics `t" -foreground Gray
					foreach ($database in $SQL_Instance.Databases){
						if ("master","model","msdb","tempdb" -NotContains $database.name){
							Write-Host "DB : $database `t`t" -NoNewLine
							$AutoUpdateStatisticsEnabled  = Select-Object -ExpandProperty AutoUpdateStatisticsEnabled  -InputObject $database
							if (!$AutoUpdateStatisticsEnabled)		{ Write-Host -foreground green "OK" } else  {Write-Host -foreground red "Failed" }
							$user_db | where { $_.name -eq $database.name} | Add-Member -Type NoteProperty -Name "AutoUpdateStatistics" -Value $AutoUpdateStatisticsEnabled
						}
					}
					Write-Host "AutoUpdateStatisticsEnabled  : `t`t`t`t(should be inactive)"
					$check = New-Object -TypeName PSObject
					Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "Auto update statistics"
					Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if($AutoUpdateStatisticsEnabled) {"OK"} else  {"Failed"})
					Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "Parameter AutoUpdateStatistics should be disable on user databases"
					$user_checks += $check

					Write-Host "`n> Check Backups" -foreground Gray
					$LastWeek = Get-Date
					$LastWeek=$LastWeek.AddDays(-7)
					$Yesterday = Get-Date
					$Yesterday=$Yesterday.AddDays(-1)
					foreach ($database in $SQL_Instance.Databases){
						if ("master","model","msdb","tempdb" -NotContains $database.name){
							Write-Host "DB : $database `t`t"
							Write-Host "`t RecoveryModel $($database.RecoveryModel)"
							Write-Host "`t Last Backup  `t`t $($database.LastBackupDate)" -NoNewLine
							if($($database.LastBackupDate) -ge $LastWeek)
								{ Write-Host "`t OK" -foreground green }
							else{ 
								Write-Host "`t Failed" -foreground red 
								if($userdb_backups_ok) {$userdb_backups_ok = $FALSE}
							}
							$user_db | where { $_.name -eq $database.name} | Add-Member -Type NoteProperty -Name "Recovery Model" 	-Value $database.RecoveryModel
							$user_db | where { $_.name -eq $database.name} | Add-Member -Type NoteProperty -Name "Last Full Backup" -Value $database.LastBackupDate
							if($($database.RecoveryModel) -match "FULL"){
								Write-Host "`t Last Log Backup  `t $($database.LastLogBackupDate)" -NoNewLine
								if($($database.LastLogBackupDate) -ge $Yesterday) 
									{ Write-Host "`t OK" -foreground green }
								else{ 
									Write-Host "`t Failed" -foreground red 
									if($userdb_backups_ok) {$userdb_backups_ok = $FALSE}
								}
								$user_db | where { $_.name -eq $database.name} | Add-Member -Type NoteProperty -Name "Last Log Backup" -Value $database.LastLogBackupDate -Force
							}
						}
					}
					$check = New-Object -TypeName PSObject
					Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "Backups"
					Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if($userdb_backups_ok) {"OK"} else  {"Failed"})
					Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "userDB should be backed up less than 7 days + db in FULL recovery mode transaction log backed up less than 1 day"
					$user_checks += $check
					
					# NTFS Checks
					Write-Host "`n> Check NTFS cluster size `t" -foreground Gray
					$Drives = $(Compare-Object $DiskDrive4Data $DiskDrive4Log -PassThru -IncludeEqual)
					foreach ($aMountPoint in $mountPointList){
						if( $Drives -Contains $($aMountPoint)){
							Write-Host "Disk : $($aMountPoint) cluster size : $($(Get-NTFSInfo $($aMountPoint)).bytes_per_cluster)`t`t" -NoNewLine
							if ($(Get-NTFSInfo $($aMountPoint)).bytes_per_cluster -eq 65536)		{ 
								Write-Host -foreground green "OK" 
							} else  {
								Write-Host -foreground red "Failed" 
								if($NTFS_cluster_ok) { $NTFS_cluster_ok=$FALSE }
							}
						}
					}
					Write-Host "NTFS cluster size (should be 64KB)"
					Write-Host ""
					$check = New-Object -TypeName PSObject
					Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "NTFS volumes w/ 64KB cluster size"
					Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if($NTFS_cluster_ok) {"OK"} else  {"Failed"})
					Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "userDB should access only NTFS partition with 64KB cluster size"
					$user_checks += $check
					
					$HTML_userdb += $user_checks | Convertto-HTML -Fragment
					$HTML_userdb += "`nFiles: <a id=`"user_Header_$InstanceName`" href=`"javascript:toggle2('userdb_param_$InstanceName','user_Header_$InstanceName');`" >Hide details</a>`n"
					$HTML_userdb += "<div id=`"userdb_param_$InstanceName`" style=`"display: block;`">"
					$HTML_userdb += $user_db | Convertto-HTML -Fragment -property "Name","Data volume(s)","Log volume(s)","Collation","AutoUpdateStatistics","Recovery Model","Last Full Backup","Last Log Backup"
					$HTML_userdb +="`n</div>"
				} else {
					Write-Host "0 users' database available" -foreground red
					$HTML_userdb +="`nThere is no available user database..."
				}
        }else{
            Write-Host "0 users' database" -foreground red
			$HTML_userdb +="`nThere is no user database..."
        }
		
		# Qualify Farm size (Small, Medium, Large, VeryLarge)
		$farm_checks = @()
		
		# Compute DB size 
		Write-Host "`n> Qualify Farm size" -foreground Gray
		$DBSizeSum = 0		
		foreach ($database in $SQL_Instance.Databases){
			if ("master","model","msdb","tempdb" -NotContains $database.name){
				$DBSizeSum += $($database.size) #in MB
			}
		}
		$farmSize = "S"
		if( $DBSizeSum -gt 2147483648 ) { # >2TB 
			$farmSize = "VL"
		}elseif( $DBSizeSum -gt 1073741824 ) { # >1TB 
			$farmSize = "L"
		}elseif( $DBSizeSum -gt 524288000 ) { # >500MB 
			$farmSize = "M"
		}else {
			$farmSize = "S"
		}
		Write-Host "SUM database size : $([decimal]::round($DBSizeSum)) MB; Farm Size : $farmSize (in Small, Medium, Large, VeryLarge)"
		
		#Databases checks
		$HTML_farm ="`n<h3>Farm sizing</h3>"
		$HTML_farm+="`nAll user databases size = $([decimal]::round($DBSizeSum)) MB</br>"
		$HTML_farm+="`nSharepoint size is $farmSize (in Small, Medium, Large, VeryLarge)</br>"
		
		# Memory checks
		Write-Host "`n> Check SQL MaxMemory `t`t" -NoNewLine  -foreground Gray
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "SQL Max Memory parameter"
		
		$MaxMemory = $SQL_Instance.Configuration.MaxServerMemory.ConfigValue
        if($MaxMemory -eq 2147483647)
        {
                Write-Host -foreground red "Failed (MaxMemory not configured)" 
                Write-Host "SQL MaxMemory : $MaxMemory MB`t`t"
				Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value "Not configured"
				Add-Member -InputObject $check -Type NoteProperty -Name "Status" -Value "Failed"
				Add-Member -InputObject $check -Type NoteProperty -Name "Comment" -Value "SQL Server max memory should be configured"
        }
        else{
				Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $MaxMemory
		        switch ($farmSize) { 
			        "S"  {if ($MaxMemory -ge 8192)		{ Write-Host -foreground green "OK" ; Add-Member -InputObject $check -Type NoteProperty -Name "Status" -Value "OK" } else  {Write-Host -foreground red "Failed" ; Add-Member -InputObject $check -Type NoteProperty -Name "Status" -Value "Failed" }}
			        "M"  {if ($MaxMemory -ge 16384)		{ Write-Host -foreground green "OK" ; Add-Member -InputObject $check -Type NoteProperty -Name "Status" -Value "OK" } else  {Write-Host -foreground red "Failed" ; Add-Member -InputObject $check -Type NoteProperty -Name "Status" -Value "Failed" }}
			        "L"  {if ($MaxMemory -ge 32768)		{ Write-Host -foreground green "OK" ; Add-Member -InputObject $check -Type NoteProperty -Name "Status" -Value "OK" } else  {Write-Host -foreground red "Failed" ; Add-Member -InputObject $check -Type NoteProperty -Name "Status" -Value "Failed" }}
			        "VL" {if ($MaxMemory -ge 65536)		{ Write-Host -foreground green "OK" ; Add-Member -InputObject $check -Type NoteProperty -Name "Status" -Value "OK" } else  {Write-Host -foreground red "Failed" ; Add-Member -InputObject $check -Type NoteProperty -Name "Status" -Value "Failed" }}
		        }
		        Write-Host "SQL MaxMemory : $MaxMemory MB`t`t" -NoNewLine
		        switch ($farmSize) {
			        "S" { Write-Host "(should be >8GB)"  ; Add-Member -InputObject $check -Type NoteProperty -Name "Comment" -Value "SQL Server max memory should be >8GB"}
			        "M" { Write-Host "(should be >16GB)" ; Add-Member -InputObject $check -Type NoteProperty -Name "Comment" -Value "SQL Server max memory should be >16GB"}
			        "L" { Write-Host "(should be >32GB)" ; Add-Member -InputObject $check -Type NoteProperty -Name "Comment" -Value "SQL Server max memory should be >32GB"}
			        "VL"{ Write-Host "(should be >64GB)" ; Add-Member -InputObject $check -Type NoteProperty -Name "Comment" -Value "SQL Server max memory should be >64GB"}
		        }
        }
		$farm_checks += $check
		
		Write-Host "`n> Check OS memory `t`t" -NoNewLine -foreground Gray
		$OSMemory = Select-Object -ExpandProperty PhysicalMemory -InputObject $SQL_Instance
		if ($OSMemory -gt $MaxMemory)		{ Write-Host -foreground green "OK" } else  {Write-Host -foreground red "Failed" }
		Write-Host "OS memory : $OSMemory MB`t`t(should be >SQLMaxMemory = $MaxMemory MB)"		
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "OS memory"
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $OSMemory
		Add-Member -InputObject $check -Type NoteProperty -Name "Status"			-Value $(if($OSMemory -gt $MaxMemory) {"OK"} else  {"Failed"})
		Add-Member -InputObject $check -Type NoteProperty -Name "Comment" 			-Value "OS Memory should be larger than SQL max memory (swapping issue)"
		$farm_checks += $check
		
		# CPU Checks
		$cpuCount=0
		Write-Host "`n> Check Number of CPU `t`t" -NoNewLine -foreground Gray
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "CPU number"
		foreach($cpu in Get-WmiObject Win32_Processor -property NumberOfCores, NumberOfLogicalProcessors){
			$cpuCount += $cpu.NumberOfCores * $cpu.NumberOfLogicalProcessors
		}
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $cpuCount
		switch ($farmSize) { 
			"S"  {if ($cpuCount -ge 4)		{ Write-Host -foreground green "OK" ; Add-Member -InputObject $check -Type NoteProperty -Name "Status" -Value "OK" } else  {Write-Host -foreground red "Failed" ; Add-Member -InputObject $check -Type NoteProperty -Name "Status" -Value "Failed" }}
			"M"  {if ($cpuCount -ge 4)		{ Write-Host -foreground green "OK" ; Add-Member -InputObject $check -Type NoteProperty -Name "Status" -Value "OK" } else  {Write-Host -foreground red "Failed" ; Add-Member -InputObject $check -Type NoteProperty -Name "Status" -Value "Failed" }}
			"L"  {if ($cpuCount -ge 8)		{ Write-Host -foreground green "OK" ; Add-Member -InputObject $check -Type NoteProperty -Name "Status" -Value "OK" } else  {Write-Host -foreground red "Failed" ; Add-Member -InputObject $check -Type NoteProperty -Name "Status" -Value "Failed" }}
			"VL" {if ($cpuCount -ge 8)		{ Write-Host -foreground green "OK" ; Add-Member -InputObject $check -Type NoteProperty -Name "Status" -Value "OK" } else  {Write-Host -foreground red "Failed" ; Add-Member -InputObject $check -Type NoteProperty -Name "Status" -Value "Failed" }}
		}
		Write-Host "Detected CPU : $cpuCount`t`t" -NoNewLine
		switch ($farmSize) {
			"S" { Write-Host "(should be >4)" ; Add-Member -InputObject $check -Type NoteProperty -Name "Comment" -Value "Server should have 4 or more CPU"}
			"M" { Write-Host "(should be >4)" ; Add-Member -InputObject $check -Type NoteProperty -Name "Comment" -Value "Server should have 4 or more CPU"}
			"L" { Write-Host "(should be >8)" ; Add-Member -InputObject $check -Type NoteProperty -Name "Comment" -Value "Server should have 4 or more CPU"}
			"VL"{ Write-Host "(should be >8)" ; Add-Member -InputObject $check -Type NoteProperty -Name "Comment" -Value "Server should have 4 or more CPU"}
		}
		$farm_checks += $check
		$HTML_farm += $farm_checks | Convertto-HTML -Fragment
		
		## Compose HTML portion for the instance :
		$HMTL_instances += $HTML_connection + $HTML_instance + $HTML_farm + "`n<h3>Database parameters</h3>" + $HTML_userdb + $HTML_modeldb + $HTML_tempdb
	}
}
$HTML_summary += "`n</ul>"
$HMTL_instances += $end_code

# Write HTML file
ConvertTo-HTML -title "SQL Server checklist" -Head $head_code -PreContent $($HMTL_title + $HTML_summary) -PostContent $HMTL_instances > $($scriptPath + "\CheckList_MSSQL_Shpt.html")
Write-Host ""
Write-Host ". End ."
Write-Host "Report saved : " $($scriptPath + "\CheckList_MSSQL_Shpt.html")
Write-Host ""
Write-Host ""

Pop-Location

exit 0
