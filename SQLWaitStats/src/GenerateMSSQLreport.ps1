#########################################################################################################
# Powershell script to install a DataCollectorSet for MS SQL
#
# Usage : Execute script from Powershell command line
#		  Require Functions_MSSQL.ps1 file in same directory
#
# Run : C:\SetupPerfMon_collectors_for_MSSQL.ps1
#
#########################################################################################################
# History :
#  - 0.1 - 15/05/2014 : Creation
#  - 0.2 - 13/08/2014 : Generate parameter report
#  - 0.3 - 19/07/2015 : Added checks on instance and user databases
#  - 0.4 - 22/07/2015 : Added SQL Agent job + Cluster infos
#########################################################################################################
$version = "0.4"
Write-Host "Starting $($MyInvocation.MyCommand).Name v$version"
$HMTL_title = "<h1>Report SQL Server parameters</h1>"
$HMTL_title+= "`n<i>$($MyInvocation.MyCommand).Name v$version</i>`n"

$timestamp 	= [DateTime]::Now.ToString("yyyyMMdd_HHmmss")
if( -Not $timestamp) { $timestamp = "0000"}

## Import functions
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
. "$scriptPath\Functions_MSSQL.ps1"

$output_HTML_file 	= $($scriptPath + "\$($($MyInvocation.MyCommand).Name)_output_$(hostname)_$timestamp.html")

## Load SQL Server Management Objects (SMO)
loadModule

## Script must be executed with admin privileges
if (!(Test-IsAdmin)){
	throw "Please run this script with admin priviliges"
}

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
				if (StringIsNullOrWhitespace($connection_string) -ne $true){
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
		Write-Host "Instance Name : $InstanceName"
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "Instance Name"
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value"		-Value $InstanceName
		$instance_checks += $check
		
		Write-Host "`n> Check : FCInstance `t`t" -foreground Gray
		$IsClustered = Select-Object -ExpandProperty IsClustered -InputObject $SQL_Instance -ErrorAction Stop
		Write-Host "Instance Name : $IsClustered"
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "IsClustered"
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value"		-Value $IsClustered
		$instance_checks += $check
		
		Write-Host "`n> Check : AlwaysOn `t`t" -foreground Gray
		$IsHadrEnabled = Select-Object -ExpandProperty IsHadrEnabled -InputObject $SQL_Instance -ErrorAction Stop
		Write-Host "Instance Name : $IsHadrEnabled"
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "IsHadrEnabled"
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value"		-Value $IsHadrEnabled
		$instance_checks += $check
		
		Write-Host "`n> Check instance version `t`t" -NoNewLine -foreground Gray
		$Version = $([String]$SQL_Instance.Version)
		$VersionMajor = $([String]$($SQL_Instance.Version).Major)
		Write-Host "Version : $Version"
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "Version"
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value"		-Value $Version
		$instance_checks += $check
		
		Write-Host "`n> Check default instance collation `t`t" -NoNewLine -foreground Gray
		$Collation = Select-Object -ExpandProperty Collation -InputObject $SQL_Instance
		Write-Host "Collation : $Collation"
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "Collation"
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value"		-Value $Collation
		$instance_checks += $check
		
		Write-Host "`n> Check Max DOP `t`t" -NoNewLine -foreground Gray
		$MaxDOP = $SQL_Instance.Configuration.MaxDegreeOfParallelism.ConfigValue
		Write-Host "SQL Max DOP : $MaxDOP"
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "Max degree of parallelism"
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value"		-Value $MaxDOP
		$instance_checks += $check
		
		Write-Host "`n> Check Fill Factor `t`t" -NoNewLine -foreground Gray
		$FillFactor = $SQL_Instance.Configuration.FillFactor.ConfigValue
		Write-Host "SQL FillFactor : $FillFactor"
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "Fill Factor"
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value"		-Value $FillFactor
		$instance_checks += $check
		
		## Network checks
		Write-Host "`n> Check TCP enabled `t`t" -NoNewLine -foreground Gray
		$mc = new-object ('Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer') localhost
		$tcp = $($mc.ServerInstances[$AnInstanceName]).ServerProtocols['Tcp']
		$TCPEnabled = $Tcp.IsEnabled
		Write-Host "TCP Enabled : $TCPEnabled"
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "TCP connection"
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value"	 	-Value $TCPEnabled
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
		Write-Host "Listener port : $FixedPortNum"
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "Fixed listener port number"
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $([string]$FixedPortNum)
		$instance_checks += $check
	
 		Write-Host "`n> Check Dynamic Port Number `t" -NoNewLine -foreground Gray
		Write-Host "Listener dynamic port : $DynamicPortNum"
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "Dynamic listener port numbers"
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $([string]$DynamicPortNum)
		$instance_checks += $check
		
		# Memory check
		Write-Host "`n> Check SQL MaxMemory `t`t" -NoNewLine  -foreground Gray
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "SQL Max Memory parameter (MB)"
		
		$MaxMemory = $SQL_Instance.Configuration.MaxServerMemory.ConfigValue
        if($MaxMemory -eq 2147483647)
        {
                Write-Host -foreground red "Failed (MaxMemory not configured)" 
                Write-Host "SQL MaxMemory : $MaxMemory MB`t`t"
				Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value "Not configured"
        }
        else{
				Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $MaxMemory
		        Write-Host "SQL MaxMemory : $MaxMemory MB`t`t" -NoNewLine
        }
		$instance_checks += $check
		
		Write-Host "`n> Check OS memory `t`t" -NoNewLine -foreground Gray
		$OSMemory = Select-Object -ExpandProperty PhysicalMemory -InputObject $SQL_Instance
		Write-Host "OS memory : $OSMemory MB`t`t(should be >SQLMaxMemory = $MaxMemory MB)"		
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "OS memory (MB)"
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $OSMemory
		$instance_checks += $check
		
		# CPU Check
		$cpuCount=0
		Write-Host "`n> Check Number of CPU `t`t" -NoNewLine -foreground Gray
		$check = New-Object -TypeName PSObject
		Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "CPU number"
		foreach($cpu in Get-WmiObject Win32_Processor -property NumberOfCores, NumberOfLogicalProcessors){
			$cpuCount += $cpu.NumberOfLogicalProcessors
		}
		Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $cpuCount
		$instance_checks += $check
		
		$HTML_instance += $instance_checks | Convertto-HTML -Fragment
		
		#MS Cluster checks
		$HTML_cluster =""
		if ($IsHadrEnabled -or $IsClustered){
			Write-Host "`n> Check : Clustered `t`t" -foreground Gray
			Import-Module failoverclusters
			$ClusterName = Select-Object -ExpandProperty ClusterName -InputObject $SQL_Instance -ErrorAction Stop
			$Cluster = Get-Cluster -name $ClusterName
			$HTML_cluster ="`n<h3>OS Cluster configuration</h3>"
			
			#$cluster_checks = @()
			#Write-Host "Cluster Name : $ClusterName"
			#$check = New-Object -TypeName PSObject
			#Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "OS Cluster Name"
			#Add-Member -InputObject $check -Type NoteProperty -Name "Current value"		-Value $ClusterName
			#$cluster_checks += $check
			#
			#Write-Host "`n> Check : Quorum `t`t" -foreground Gray
			#$ClusterName = Select-Object -ExpandProperty ClusterName -InputObject $SQL_Instance -ErrorAction Stop
			#Write-Host "Cluster Name : $ClusterName"
			#$check = New-Object -TypeName PSObject
			#Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "OS Cluster Name"
			#Add-Member -InputObject $check -Type NoteProperty -Name "Current value"		-Value $ClusterName
			#$cluster_checks += $check
			#
			#$HTML_cluster += $cluster_checks | Convertto-HTML -Fragment
			
			$HTML_cluster += Get-ClusterQuorum -cluster $Cluster | select Cluster,QuorumResource, QuorumType | Convertto-HTML -Fragment
			
			$HTML_cluster +="`n<h4>Cluster nodes</h4>"
			$HTML_cluster += Get-ClusterNode -cluster $CLuster | select ID,NodeName,State,DrainStatus,NodeWeight,DynamicWeight | Convertto-HTML -Fragment
			
		}
		
		#Databases checks		
		# model check
		$HTML_modeldb="`n<h4>model Database</h4>"
		$modeldb_checks = @()
		$modeldb_files = @()
		Write-Host "`n> Check model DB `t" -foreground Gray
		foreach ($database in $SQL_Instance.Databases){
			if ($database.name -eq "model"){
				$AutoUpdateStatisticsEnabled  = Select-Object -ExpandProperty AutoUpdateStatisticsEnabled  -InputObject $database
				Write-Host " - model DB AutoUpdateStatistics: $AutoUpdateStatisticsEnabled"
				$check = New-Object -TypeName PSObject
				Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "modelDB AutoUpdateStatistics parameter"
				Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $([string]$AutoUpdateStatisticsEnabled)
				$modeldb_checks += $check
			
				$modelCollation  = Select-Object -ExpandProperty Collation  -InputObject $database
				Write-Host " - model DB Collation: $modelCollation"
				$check = New-Object -TypeName PSObject
				Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "modelDB collation"
				Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $([string]$modelCollation)
				$modeldb_checks += $check
				
				$modelRecoveryModel  = Select-Object -ExpandProperty RecoveryModel  -InputObject $database
				Write-Host " - model DB recovery model: $modelRecoveryModel"
				$check = New-Object -TypeName PSObject
				Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "modelDB recovery model"
				Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $([string]$modelRecoveryModel)
				$modeldb_checks += $check

				$dataSize = 0
				$fileGroups = $database.FileGroups
				ForEach ($fg in $fileGroups){
					If ($fg) {
						ForEach ($dataFiles in $fg.Files){
							$dataSize += $($dataFiles.size) # in KB
							Write-Host "data file $($dataFiles.ID) size : $($dataFiles.size)KB`t autoGrowth : $($dataFiles.Growth) $($dataFiles.GrowthType)`t`t"
							$file = New-Object -TypeName PSObject
							Add-Member -InputObject $file -Type NoteProperty -Name "LogicalName" 	-Value $([string]$dataFiles.Name)
							Add-Member -InputObject $file -Type NoteProperty -Name "PhysicalName" 	-Value $([string]$dataFiles.FileName)
							Add-Member -InputObject $file -Type NoteProperty -Name "Type" 			-Value "Data"
							Add-Member -InputObject $file -Type NoteProperty -Name "Size (KB)" 		-Value $([string]$dataFiles.size)
							Add-Member -InputObject $file -Type NoteProperty -Name "AutoGrowth" 	-Value $([string]$dataFiles.Growth + [string]$dataFiles.GrowthType)
							$modeldb_files += $file
						}
					}
				}
				Write-Host " - Total model DB data file size: $dataSize KB`t`t"	
				
				$logSize = 0
				ForEach ($logFiles in $database.LogFiles){
					$logSize += $($logFiles.size)
					Write-Host "log  file $($logFiles.ID) size : $($logFiles.size)KB`t autoGrowth : $($logFiles.Growth) $($logFiles.GrowthType)`t`t"
					$file = New-Object -TypeName PSObject
					Add-Member -InputObject $file -Type NoteProperty -Name "LogicalName" 	-Value $([string]$logFiles.Name)
					Add-Member -InputObject $file -Type NoteProperty -Name "PhysicalName" 	-Value $([string]$logFiles.FileName)					
					Add-Member -InputObject $file -Type NoteProperty -Name "Type" 			-Value "TransactionLog"
					Add-Member -InputObject $file -Type NoteProperty -Name "Size (KB)" 		-Value $([string]$logFiles.size)
					Add-Member -InputObject $file -Type NoteProperty -Name "AutoGrowth" 	-Value $([string]$logFiles.Growth + [string]$logFiles.GrowthType)
					$modeldb_files += $file
				}
				Write-Host " - Total model DB log  file size: $logSize KB`t`t"
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
				$check = New-Object -TypeName PSObject
				Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "tempDB size"
				Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $([string]$database.size + "KB")
				$tempdb_checks += $check
				
				Write-Host " tempDB recovery model : $($database.RecoveryModel) `t" -NoNewLine
				$check = New-Object -TypeName PSObject
				Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "tempDB recovery model"
				Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $([string]$database.RecoveryModel)
				$tempdb_checks += $check
				
				$fileGroups = $database.FileGroups
				ForEach ($fg in $fileGroups){
					If ($fg) {
						ForEach ($dataFiles in $fg.Files){
							Write-Host " file $($dataFiles.ID) size : $($dataFiles.size) KB`t`t`t"
							Write-Host " file $($dataFiles.ID) autoGrowth : $($dataFiles.Growth) $($dataFiles.GrowthType)`t`t"
							$file = New-Object -TypeName PSObject
							Add-Member -InputObject $file -Type NoteProperty -Name "LogicalName" 	-Value $([string]$dataFiles.Name)
							Add-Member -InputObject $file -Type NoteProperty -Name "PhysicalName" 	-Value $([string]$dataFiles.FileName)
							Add-Member -InputObject $file -Type NoteProperty -Name "Type" 			-Value "Data"
							Add-Member -InputObject $file -Type NoteProperty -Name "Size (KB)" 		-Value $([string]$dataFiles.size)
							Add-Member -InputObject $file -Type NoteProperty -Name "AutoGrowth" 	-Value $([string]$dataFiles.Growth + [string]$dataFiles.GrowthType)
							$tempdb_files += $file
						}
					}
				}
				$logSize = 0
				ForEach ($logFiles in $database.LogFiles){
					$logSize += $($logFiles.size)
					Write-Host "log  file $($logFiles.ID) size : $($logFiles.size)KB`t autoGrowth : $($logFiles.Growth) $($logFiles.GrowthType)`t`t" -NoNewLine
					$file = New-Object -TypeName PSObject
					Add-Member -InputObject $file -Type NoteProperty -Name "LogicalName" 	-Value $([string]$logFiles.Name)
					Add-Member -InputObject $file -Type NoteProperty -Name "PhysicalName" 	-Value $([string]$logFiles.FileName)
					Add-Member -InputObject $file -Type NoteProperty -Name "Type" 			-Value "TransactionLog"
					Add-Member -InputObject $file -Type NoteProperty -Name "Size (KB)" 		-Value $([string]$logFiles.size)
					Add-Member -InputObject $file -Type NoteProperty -Name "AutoGrowth" 	-Value $([string]$logFiles.Growth + [string]$logFiles.GrowthType)
					$tempdb_files += $file
				}
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
		if ($SQL_Instance.Databases.count -gt 4) {
				# Generate db objects
				foreach ($database in $SQL_Instance.Databases){
					if ($database.status -NotLike "*Normal*") 					{ continue }
					if ("master","model","msdb","tempdb" -Contains $database.name) 	{ continue }
					$db = New-Object -TypeName PSObject
					Add-Member -InputObject $db -Type NoteProperty -Name "Name" -Value $database.name
					Add-Member -InputObject $db -Type NoteProperty -Name "Last Log Backup" -Value "-"
					$user_db += $db
				}
				
				if ($user_db.count -ne 0) {
					$DiskDrive4Data = @();
					$DiskDrive4Log  = @();
					
					Write-Host "`n> Check files location `t" -foreground Gray
					$mountPointList = Get-WmiObject Win32_Volume -Filter "DriveType='3'" -property name | sort-object -property @{Expression={$_.name.length};Descending=$true} | format-table -property name -HideTableHeaders | out-string -stream | % {$_.Trim()}
					
					foreach ($database in $SQL_Instance.Databases){
						if ($database.status -NotLike "*Normal*") 						{ continue }
						if ("master","model","msdb","tempdb" -Contains $database.name) 	{ continue }
						$fileGroups = $database.FileGroups
						$DBDiskDrive4Data = @();
						$DBDiskDrive4Log  = @();
						$DBDataFiles="";
						$DBLogFiles ="";
						ForEach ($fg in $fileGroups){
							If ($fg) {
								ForEach ($dataFiles in $fg.Files){
									$DBDiskDrive4Data += get-mountPoint $mountPointList $dataFiles.FileName
									$DBDataFiles += "$($dataFiles.FileName) `($($dataFiles.Size/1024) MB`) - "
								}
							}
						}
						ForEach ($logFiles in $database.LogFiles){
							$DBDiskDrive4Log += get-mountPoint $mountPointList $logFiles.FileName
							$DBLogFiles += "$($logFiles.FileName) `($($logFiles.Size/1024) MB`) - "
						}
						$user_db | where { $_.name -eq $database.name} | Add-Member -Type NoteProperty -Name "Datafile" -Value $DBDataFiles
						$user_db | where { $_.name -eq $database.name} | Add-Member -Type NoteProperty -Name "Logfile"  -Value $DBLogFiles
						
						$DiskDrive4Data += $DBDiskDrive4Data
						$DiskDrive4Log  += $DBDiskDrive4Log
					}
					$DiskDrive4Data = $DiskDrive4Data | Sort-Object | Get-Unique
					$DiskDrive4Log  = $DiskDrive4Log  | Sort-Object | Get-Unique
					if ( !$(StringIsNullOrWhitespace($DiskDrive4Data)) -and !$(StringIsNullOrWhitespace($DiskDrive4Log))){
						Write-Host " Data disk drive : "$DiskDrive4Data
						Write-Host " Log  disk drive : "$DiskDrive4Log
						
						$check = New-Object -TypeName PSObject
						Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "Disk access"
						Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $("Data drive(s):" + [string]$DiskDrive4Data + " - Log drive(s):" + [string]$DiskDrive4Log)
						$user_checks += $check
					}else{
						Write-Host "Cannot retrieve Data and Log disk drive..."
					}
					
					#Non default parameters
					$userDB_specific_param	= @()
					Write-Host "`n> Check Non-default parameter" -foreground Gray
					foreach ($database in $SQL_Instance.Databases){
						if ("master","model","msdb","tempdb" -NotContains $database.name){
							# Collation
							if ($database.collation -ne $Collation){
								$check = New-Object -TypeName PSObject
								Add-Member -InputObject $check -Type NoteProperty -Name "Database" 			-Value $($database.name)
								Add-Member -InputObject $check -Type NoteProperty -Name "Parameter" 		-Value "Collation"
								Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $($database.collation)
								$userDB_specific_param += $check
								Write-Host "$($database.name) Collation is $($database.collation)"
							}
							# CompatibilityLevel
							$database_CompatibilityLevel = $([string]$($database.CompatibilityLevel)).replace("Version","")
							if ($database_CompatibilityLevel -notMatch $($VersionMajor+0)){
								$check = New-Object -TypeName PSObject
								Add-Member -InputObject $check -Type NoteProperty -Name "Database" 			-Value $($database.name)
								Add-Member -InputObject $check -Type NoteProperty -Name "Parameter" 		-Value "CompatibilityLevel"
								Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $database_CompatibilityLevel
								$userDB_specific_param += $check
								Write-Host "$($database.name) CompatibilityLevel is $database_CompatibilityLevel"
							}
							# AutoClose
							if ($($database.AutoClose) -notMatch "False"){
								$check = New-Object -TypeName PSObject
								Add-Member -InputObject $check -Type NoteProperty -Name "Database" 			-Value $($database.name)
								Add-Member -InputObject $check -Type NoteProperty -Name "Parameter" 		-Value "AutoClose"
								Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $($database.AutoClose)
								$userDB_specific_param += $check
								Write-Host "$($database.name) AutoClose is $($database.AutoClose)"
							}
							# AutoShrink
							if ($($database.AutoShrink) -notMatch "False"){
								$check = New-Object -TypeName PSObject
								Add-Member -InputObject $check -Type NoteProperty -Name "Database" 			-Value $($database.name)
								Add-Member -InputObject $check -Type NoteProperty -Name "Parameter" 		-Value "AutoShrink"
								Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $($database.AutoShrink)
								$userDB_specific_param += $check
								Write-Host "$($database.name) AutoShrink is $($database.AutoShrink)"
							}
							# AutoCreateStatisticsEnabled
							if ($($database.AutoCreateStatisticsEnabled) -notMatch "True"){
								$check = New-Object -TypeName PSObject
								Add-Member -InputObject $check -Type NoteProperty -Name "Database" 			-Value $($database.name)
								Add-Member -InputObject $check -Type NoteProperty -Name "Parameter" 		-Value "AutoCreateStatistics"
								Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $($database.AutoCreateStatisticsEnabled)
								$userDB_specific_param += $check
								Write-Host "$($database.name) AutoCreateStatistics is $($database.AutoCreateStatisticsEnabled)"
							}
							# AutoUpdateStatisticsEnabled
							if ($($database.AutoUpdateStatisticsEnabled) -notMatch "True"){
								$check = New-Object -TypeName PSObject
								Add-Member -InputObject $check -Type NoteProperty -Name "Database" 			-Value $($database.name)
								Add-Member -InputObject $check -Type NoteProperty -Name "Parameter" 		-Value "AutoUpdateStatistics"
								Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $($database.AutoUpdateStatisticsEnabled)
								$userDB_specific_param += $check
								Write-Host "$($database.name) AutoUpdateStatistics is $($database.AutoUpdateStatisticsEnabled)"
							}
							# AutoUpdateStatisticsAsync
							if ($($database.AutoUpdateStatisticsAsync) -notMatch "False"){
								$check = New-Object -TypeName PSObject
								Add-Member -InputObject $check -Type NoteProperty -Name "Database" 			-Value $($database.name)
								Add-Member -InputObject $check -Type NoteProperty -Name "Parameter" 		-Value "AutoUpdateStatisticsAsync"
								Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $($database.AutoUpdateStatisticsAsync)
								$userDB_specific_param += $check
								Write-Host "$($database.name) AutoUpdateStatisticsAsync is $($database.AutoUpdateStatisticsAsync)"
							}
							# SnapshotIsolationState
							if ($($database.SnapshotIsolationState) -notMatch "Disabled"){
								$check = New-Object -TypeName PSObject
								Add-Member -InputObject $check -Type NoteProperty -Name "Database" 			-Value $($database.name)
								Add-Member -InputObject $check -Type NoteProperty -Name "Parameter" 		-Value "SnapshotIsolationState"
								Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $($database.SnapshotIsolationState)
								$userDB_specific_param += $check
								Write-Host "$($database.name) SnapshotIsolationState is $($database.SnapshotIsolationState)"
							}
							# IsReadCommittedSnapshotOn
							if ($($database.IsReadCommittedSnapshotOn) -notMatch "False"){
								$check = New-Object -TypeName PSObject
								Add-Member -InputObject $check -Type NoteProperty -Name "Database" 			-Value $($database.name)
								Add-Member -InputObject $check -Type NoteProperty -Name "Parameter" 		-Value "IsReadCommittedSnapshotOn"
								Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $($database.IsReadCommittedSnapshotOn)
								$userDB_specific_param += $check
								Write-Host "$($database.name) ReadCommittedSnapshotOn is $($database.IsReadCommittedSnapshotOn)"
							}
							# ReadOnly
							if ($($database.ReadOnly) -notMatch "False"){
								$check = New-Object -TypeName PSObject
								Add-Member -InputObject $check -Type NoteProperty -Name "Database" 			-Value $($database.name)
								Add-Member -InputObject $check -Type NoteProperty -Name "Parameter" 		-Value "ReadOnly"
								Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $($database.ReadOnly)
								$userDB_specific_param += $check
								Write-Host "$($database.name) ReadOnly is $($database.ReadOnly)"
							}
							# EncryptionEnabled
							if ($($database.EncryptionEnabled) -notMatch "False"){
								$check = New-Object -TypeName PSObject
								Add-Member -InputObject $check -Type NoteProperty -Name "Database" 			-Value $($database.name)
								Add-Member -InputObject $check -Type NoteProperty -Name "Parameter" 		-Value "EncryptionEnabled"
								Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $($database.EncryptionEnabled)
								$userDB_specific_param += $check
								Write-Host "$($database.name) EncryptionEnabled is $($database.EncryptionEnabled)"
							}
							# PageVerify
							if ($($database.PageVerify) -notMatch "Checksum"){
								$check = New-Object -TypeName PSObject
								Add-Member -InputObject $check -Type NoteProperty -Name "Database" 			-Value $($database.name)
								Add-Member -InputObject $check -Type NoteProperty -Name "Parameter" 		-Value "PageVerify"
								Add-Member -InputObject $check -Type NoteProperty -Name "Current value" 	-Value $($database.PageVerify)
								$userDB_specific_param += $check
								Write-Host "$($database.name) PageVerify is $($database.PageVerify)"
							}
						}
					}
					
					#Backups
					Write-Host "`n> Check Backups" -foreground Gray
					foreach ($database in $SQL_Instance.Databases){
						if ("master","model","msdb","tempdb" -NotContains $database.name){
							Write-Host "DB : $database `t`t"
							Write-Host "`t RecoveryModel $($database.RecoveryModel)"
							Write-Host "`t Last Backup  `t`t $($database.LastBackupDate)"
							$user_db | where { $_.name -eq $database.name} | Add-Member -Type NoteProperty -Name "Recovery Model" 	-Value $database.RecoveryModel
							$user_db | where { $_.name -eq $database.name} | Add-Member -Type NoteProperty -Name "Last Full Backup" -Value $database.LastBackupDate
							if($($database.RecoveryModel) -match "FULL"){
								Write-Host "`t Last Log Backup  `t $($database.LastLogBackupDate)"
								$user_db | where { $_.name -eq $database.name} | Add-Member -Type NoteProperty -Name "Last Log Backup" -Value $database.LastLogBackupDate -Force
							}
						}
					}
					
					# NTFS Checks
					Write-Host "`n> Check NTFS cluster size `t" -foreground Gray
					$Drives = $(Compare-Object $DiskDrive4Data $DiskDrive4Log -PassThru -IncludeEqual)
					foreach ($aMountPoint in $mountPointList){
						if( $Drives -Contains $($aMountPoint)){
							Write-Host "Disk : $($aMountPoint) cluster size : $($(Get-NTFSInfo $($aMountPoint)).bytes_per_cluster)`t`t"
							$check = New-Object -TypeName PSObject
							Add-Member -InputObject $check -Type NoteProperty -Name "Checked element" 	-Value "NTFS volumes w/ 64KB cluster size"
							Add-Member -InputObject $check -Type NoteProperty -Name "Current value"		-Value "$($aMountPoint) = $($(Get-NTFSInfo $($aMountPoint)).bytes_per_cluster/1024) KB"
							$user_checks += $check
						}
					}
					Write-Host "NTFS cluster size (should be 64KB)"
					Write-Host ""
					
					#HTML file block
					$HTML_userdb += "`n<h5>Files: </h5><br/>`n<a id=`"user_Header_$InstanceName`" href=`"javascript:toggle2('userdb_param_$InstanceName','user_Header_$InstanceName');`" >Hide details</a>`n"
					$HTML_userdb += "<div id=`"userdb_param_$InstanceName`" style=`"display: block;`">"
					$HTML_userdb += $user_db | Convertto-HTML -Fragment -property "Name","Datafile","Logfile","Recovery Model","Last Full Backup","Last Log Backup"
					$HTML_userdb +="`n</div>"
					#File location
					$HTML_userdb +="`n<h5>Storage specific</h5>"
					$HTML_userdb += $user_checks | Convertto-HTML -Fragment
					#Non-default parameters
					$HTML_userdb += "`n<h5>Non default parameter</h5>"
					$HTML_userdb += $userDB_specific_param | Sort-Object Database,Parameter | Convertto-HTML -Fragment
				} else {
					Write-Host "0 users' database available" -foreground red
					$HTML_userdb +="`nThere is no available user database..."
				}
        }else{
            Write-Host "0 users' database" -foreground red
			$HTML_userdb +="`nThere is no user database..."
        }
		
		# Jobs review
        Write-Host "`n> Now checking SQL jobs" -foreground Gray
		$HTML_sqlagent = "`n<h3>SQL Agent Jobs</h3>"
		$jobs 		= @()
		$jobs_steps	= @()
		foreach($oneJob in $($SQL_Instance.JobServer).Jobs){
			Write-Host "Job : $oneJob.Name"
			$job_table = $oneJob | Select Name,IsEnabled,CurrentRunStatus,LastRunDate,LastRunOutcome,NextRunDate | Convertto-HTML -as list -fragment
			$job_table[1]= $job_table[1] -replace 'td','th'
			
			$HTML_sqlagent += $job_table
			$jobs_steps	= @()
			foreach($oneStep in $($oneJob.jobSteps | Sort-Object ID)){
				$step = New-Object -TypeName PSObject
				Add-Member -InputObject $step -Type NoteProperty -Name "StepID" 			-Value $oneStep.ID
				Add-Member -InputObject $step -Type NoteProperty -Name "StepName" 			-Value $oneStep.Name
				Add-Member -InputObject $step -Type NoteProperty -Name "Command" 			-Value $oneStep.Command
				Add-Member -InputObject $step -Type NoteProperty -Name "LastRunDate" 		-Value $oneStep.LastRunDate
				Add-Member -InputObject $step -Type NoteProperty -Name "LastRunOutcome" 	-Value $oneStep.LastRunOutcome
				$jobs_steps += $step
			}
			$HTML_sqlagent += "`n<a id=`"job_Header_$($oneJob.Name)`" href=`"javascript:toggle2('job_step_$($oneJob.Name)','job_Header_$($oneJob.Name)');`" >View details</a>`n"
			$HTML_sqlagent += "<div id=`"job_step_$($oneJob.Name)`" style=`"display: none;`">"
			$HTML_sqlagent += $jobs_steps | Convertto-HTML -Fragment
			$HTML_sqlagent +="`n</div>"
		}
		
		## Compose HTML portion for the instance :
		$HMTL_instances += $HTML_connection + $HTML_instance + $HTML_cluster + $HTML_modeldb + $HTML_tempdb + "`n<h3>Database parameters</h3>" + $HTML_userdb + $HTML_sqlagent
	}
}
$HTML_summary += "`n</ul>"
$HMTL_instances += $end_code

# Write HTML file
ConvertTo-HTML -title "SQL Server checklist" -Head $head_code -PreContent $($HMTL_title + $HTML_summary) -PostContent $HMTL_instances > $output_HTML_file
Write-Host ""
Write-Host ". End ."
Write-Host "Report saved : " $output_HTML_file
Write-Host ""
Write-Host ""

Pop-Location

exit 0
