#########################################################################################################
# Powershell script to check disk performance with a SQL Server (parameter simulation)
#
# Usage : Execute script from Powershell command line
#
#########################################################################################################
# History :
#  - 0.1  - 21/09/2015 : Creation
#  - 0.2e - 22/09/2015 : Random or sequential i/o
#  - 0.4  - 08/10/2015 : Code factorisation
#  - 0.5b - 13/10/2015 : HTML rewrite
#  - 0.6  - 11/01/2016 : Correct Read-Ahead i/o size + HTML All-in-One + parameter duration
#  - 0.7  - 11/02/2016 : Add CPU Usage per tests
#  - 0.8  - 12/02/2016 : to_the_limits parameters
#  - 0.8b - 18/02/2016 : Updates on to_the_limits bench
#  - 0.9a - 08/04/2016 : Output to csv file (csv switch param)
#########################################################################################################
Param(
    [Parameter(HelpMessage="Data drive")]
    [alias("data")]
    [String] $Data_drive="C:",
    [Parameter(HelpMessage="Log drive")]
    [alias("log")]
    [String] $Log_drive="C:",
    [Parameter(HelpMessage="Duration (in minute) ; min=5mn")]
    [int] $duration = 5,
    [Parameter(HelpMessage="Write output to CSV file")]
    [alias("csv")]
    [switch] $csv_output,
    [Parameter(HelpMessage="Benchmark disks like the storage providers do. WARNING : Long test (duration)")]
    [alias("to_the_limits")]
    [switch] $to_the_limits_switch
)

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$version = "0.9a"


function generate_CSV{
	# Make a copy of previous file
	if(Test-Path $output_CSV_file){
		$previous_csv = $TRUE
		if(Test-Path "$output_CSV_file.save"){ Remove-Item "$output_CSV_file.save"}
		Copy-Item $output_CSV_file "$output_CSV_file.save"
	}
	
	#Write-Output $Data_RunDetails
	$Data_RunDetails | Export-CSV -Path $output_CSV_file
	
	if ($previous_csv){
		(Get-Content "$output_CSV_file.save") | Select-Object -Skip 2 | Out-File -Encoding ASCII -Append -FilePath $output_CSV_file
	}
}


# HTML replacements :
# PS variable				HTML in model file							HTML in output file
# $refresh					<!--#### refresh ####-->					<meta http-equiv="refresh" content="15" >
# $version					#### DiskBenchmark_MSSQL.ps1 ####			DiskBenchmark_MSSQL.ps1 v$version
# $FuncDRA_param			#### Function Read-Ahead param ####			Function Read-Ahead parameters : xxxxxxxxxxxxxxxxxxxxxxxxxx
# $dataDRA_iops				//#### dataDRA_iops ####					iops_data[0] = ["Run 1", 243, 24.78]; etc...
# $dataDRA_latency			//#### dataDRA_latency ####					Latency_data[0] = ["Run 1", [1.104, 1.415, 1.654, 2.041, 6.360]]; etc...
# $dataDRA_cores			//#### dataDRA_cores ####					//dataset[0] = [{data: [{core: '0',count: 25},  etc...],name: 'KernelMode'},{data: [{core: '0',count: 75} etc...
# $FuncDLW_param			#### Function DLW param ####				Function Lazy Writer parameters : xxxxxxxxxxxxxxxxxxxxxxxxxx
# $dataDLW_iops				//#### dataDLW_iops ####					iops_data[0] = ["Run 1", 243, 24.78]; etc...
# $dataDLW_latency			//#### dataDLW_latency ####					Latency_data[0] = ["Run 1", [1.104, 1.415, 1.654, 2.041, 11]]; etc...
# $dataDLW_cores			//#### dataDLW_cores ####					//dataset[0] = [{data: [{core: '0',count: 25},  etc...],name: 'KernelMode'},{data: [{core: '0',count: 75} etc...
# $FuncLRW_param			#### Function param LRW ####				Function Log Writer parameters : xxxxxxxxxxxxxxxxxxxxxxxxxx
# $dataLWR_iops				//#### dataLWR_iops ####					iops_data[0] = ["Run 1", 243, 24.78]; etc...
# $dataLWR_latency			//#### dataLWR_latency ####					Latency_data[0] = ["Run 1", [1.104, 1.415, 1.654, 2.041, 20]]; etc...
# $dataLWR_cores			//#### dataLWR_cores ####					//dataset[0] = [{data: [{core: '0',count: 25},  etc...],name: 'KernelMode'},{data: [{core: '0',count: 75} etc...
# $dataheatMap_data			//#### dataheatMap_data ####				//var heatMap_data = [{threads: 1, outstandings: 1, iops: 100, latency: 10.3}, {threads: 1, outstandings: 2, iops: 987, latency: 8.6}, etc... ]
function generate_HTML{
	Get-Content $model_file | 
	Foreach-Object {$_ -replace '<!--#### refresh ####-->', 			$refresh}  | 
	Foreach-Object {$_ -replace '#### DiskBenchmark_MSSQL.ps1 ####', 	$version}  | 
	Foreach-Object {$_ -replace '#### Function Read-Ahead param ####', 	$FuncDRA_param}  | 
	Foreach-Object {$_ -replace '//#### dataDRA_iops ####', 			$dataDRA_iops}  | 
	Foreach-Object {$_ -replace '//#### dataDRA_latency ####', 			$dataDRA_latency}  | 
	Foreach-Object {$_ -replace '//#### dataDRA_cores ####', 			$dataDRA_cores}  | 
	Foreach-Object {$_ -replace '#### Function DLW param ####', 		$FuncDLW_param}  | 
	Foreach-Object {$_ -replace '//#### dataDLW_iops ####', 			$dataDLW_iops}  | 
	Foreach-Object {$_ -replace '//#### dataDLW_latency ####', 			$dataDLW_latency}  | 
	Foreach-Object {$_ -replace '//#### dataDLW_cores ####', 			$dataDLW_cores}  | 
	Foreach-Object {$_ -replace '#### Function param LRW ####', 		$FuncLRW_param}  | 
	Foreach-Object {$_ -replace '//#### dataLWR_iops ####', 			$dataLWR_iops}  | 
	Foreach-Object {$_ -replace '//#### dataLWR_latency ####', 			$dataLWR_latency}  | 
	Foreach-Object {$_ -replace '//#### dataLWR_cores ####', 			$dataLWR_cores}  |  
	Foreach-Object {$_ -replace '//#### dataheatMap_data ####', 		$dataheatMap_data}  | 
	Out-File -Encoding "UTF8" $output_HTML_file
}

## Function Execute-DiskSpd
function benchmark{
	param (	[String[]]$Parameters,
			[ref]$Data_RunDetails,
			[ref]$Data_JSScript_latency,
			[ref]$Data_JSScript_iops,
			[ref]$Data_JSScript_cores,
			[String]$functionSimulated)
	Write-Output "Parameters : $Parameters"
	$i=0
	$Data_JSScript_latency.value = ""
	$Data_JSScript_iops.value = ""
	$Data_JSScript_cores.value = ""
	while($i -lt $nbr_run){
		$exe = "$scriptPath\diskspd.exe"
		&$exe $Parameters | Tee-Object -Variable result | Out-Null
		if($result){
			foreach ($line in $result) {if ($line -like "total:*") { $total=$line; break } }
			foreach ($line in $result) {if ($line -like "avg.*") { $avg=$line; break } }
			# Quartiles
			foreach ($line in $result) {if ($line -like "    min *") { $min=$line; break } }
			foreach ($line in $result) {if ($line -like "   25th *") { $Q25=$line; break } }
			foreach ($line in $result) {if ($line -like "   50th *") { $Q50=$line; break } }
			foreach ($line in $result) {if ($line -like "   75th *") { $Q75=$line; break } }
			foreach ($line in $result) {if ($line -like "   99th *") { $Q99=$line; break } }
			$mbps = $total.Split("|")[2].Trim() 
			$iops = $total.Split("|")[3].Trim()
			$latency = $total.Split("|")[4].Trim()
			$cpu = $avg.Split("|")[1].Trim()
			
			$min = $min.Split("|")[3].Trim()
			$Q25 = $Q25.Split("|")[3].Trim()
			$Q50 = $Q50.Split("|")[3].Trim()
			$Q75 = $Q75.Split("|")[3].Trim()
			$Q99 = $Q99.Split("|")[3].Trim()
			
			$check = New-Object -TypeName PSObject
			Add-Member -InputObject $check -Type NoteProperty -Name "Timestamp" 		-Value $timestamp 	
			Add-Member -InputObject $check -Type NoteProperty -Name "Function" 			-Value $functionSimulated
			Add-Member -InputObject $check -Type NoteProperty -Name "Run"				-Value $i
			Add-Member -InputObject $check -Type NoteProperty -Name "Parameters"		-Value "$Parameters"
			Add-Member -InputObject $check -Type NoteProperty -Name "IOPS"				-Value $iops
			Add-Member -InputObject $check -Type NoteProperty -Name "Throughput (MB/s)" -Value $mbps
			Add-Member -InputObject $check -Type NoteProperty -Name "Latency (ms) AVG" 		-Value $latency
			Add-Member -InputObject $check -Type NoteProperty -Name "Latency (ms) min" 		-Value $min
			Add-Member -InputObject $check -Type NoteProperty -Name "Latency (ms) Q25" 		-Value $Q25
			Add-Member -InputObject $check -Type NoteProperty -Name "Latency (ms) Q50" 		-Value $Q50
			Add-Member -InputObject $check -Type NoteProperty -Name "Latency (ms) Q75" 		-Value $Q75
			Add-Member -InputObject $check -Type NoteProperty -Name "Latency (ms) Q99" 		-Value $Q99			
			
			# Cores usage
			$UserMode 	= "name: 'UserMode'  , data:["
			$KernelMode = "name: 'KernelMode', data:["
			$get_cores=0
			foreach ($line in $result) {
				if ($line -match "^(\s)*\d{1,}")
				{	
					if($get_cores -eq 0) 	{ 
						$UserMode 	+= " { core: " + $get_cores + ",count: " + $($line.Split("|")[2].Trim() -replace ".{2}$") + " }"
						$KernelMode += " { core: " + $get_cores + ",count: " + $($line.Split("|")[3].Trim() -replace ".{2}$") + " }"
					}                                                                                                       
					else{                                                                                                   
						$UserMode 	+= ",{ core: " + $get_cores + ",count: " + $($line.Split("|")[2].Trim() -replace ".{2}$") + " }" 
						$KernelMode += ",{ core: " + $get_cores + ",count: " + $($line.Split("|")[3].Trim() -replace ".{2}$") + " }" 
					}
					
					Add-Member -InputObject $check -Type NoteProperty -Name "UserMode core$($get_cores) (%)" 	-Value $($line.Split("|")[2].Trim() -replace ".{2}$")
					Add-Member -InputObject $check -Type NoteProperty -Name "KernelMode core$($get_cores) (%)"	-Value $($line.Split("|")[3].Trim() -replace ".{2}$")
					
					$get_cores++ 
				} 
				if ($get_cores -ge 1 -and $line -match "^(-)?$") 		{ break}
			}
			$UserMode += "]"
			$KernelMode += "]"
			
			Write-Output "Run $i, $iops iops, $mbps MB/sec, $latency ms (min $min, Q25 $Q25, Q50 $Q50, Q75 $Q75, Q99 $Q99), $cpu CPU"
			$Data_JSScript_latency.value 	+= "Latency_data[$i] = [""Run $i"", [$min, $Q25, $Q50, $Q75, $Q99]];
"
			$Data_JSScript_cores.value 	+= "	dataset[$i] =	[{" + $KernelMode + "}
					,{" + $UserMode + "}];
"
			$Data_JSScript_iops.value 	+= "iops_data[$i] = [""Run $i"", $iops, $mbps];
"
			if( -Not $csv_output){ generate_HTML }
			
			$Data_RunDetails.value += $check
		}
		$i += 1
	}
}

function benchmark_to_limits([ref]$data_JS_heatMap_data){
	$data_JS_heatMap_data.value = "heatMap_data = ["
	$MaxThreads = $cpuCount * 2 # Launch max 2 threads per core
	$MaxOutstandings = 64
    
	$threads = 1
	while ($threads -le $MaxThreads ){
		$outstandings = 1
		while ($outstandings -le $MaxOutstandings){
			$DiskSPD_param = "-c1G -d$duration -r -w100 -b4K -h -W -o$outstandings -t$threads -L $TestFilePath".Split()
			$exe = "$scriptPath\diskspd.exe"
			&$exe $DiskSPD_param | Tee-Object -Variable result | Out-Null
			if($result){
				foreach ($line in $result) {if ($line -like "total:*") { $total=$line; break } }
				$iops = $total.Split("|")[3].Trim()
				$latency = $total.Split("|")[4].Trim()
				$data_JS_heatMap_data.value += "{threads: $threads, outstandings: $outstandings, iops: $iops, latency: $latency},"
				$data_JS_heatMap_data.value = $($data_JS_heatMap_data.value -replace ".{1}$") + "]"
				if( -Not $csv_output){ generate_HTML }
				$data_JS_heatMap_data.value = $($data_JS_heatMap_data.value -replace ".{1}$") + ","
			}
			$outstandings=$outstandings*2
		}
		$threads=$threads*2
	}
	$data_JS_heatMap_data.value = $($data_JS_heatMap_data.value -replace ".{1}$") + "]"
}

$refresh				= "<meta http-equiv=""refresh"" content=""15"" >"
$version				= "DiskBenchmark_MSSQL.ps1 v$version"
$FuncDRA_param			= "Function Read-Ahead parameters : "
$dataDRA_iops			= ""
$dataDRA_latency		= ""
$dataDRA_cores			= ""
$FuncDLW_param			= "Function Lazy Writer parameters : "
$dataDLW_iops			= ""
$dataDLW_latency		= ""
$dataDLW_cores			= ""
$FuncLRW_param			= "Function Log Writer parameters : "
$dataLWR_iops			= ""
$dataLWR_latency		= ""
$dataLWR_cores			= ""
$dataheatMap_data		= ""
$Data_RunDetails				= @()


$timestamp 	= [DateTime]::Now.ToString("yyyyMMdd_HHmmss")
if( -Not $timestamp) { $timestamp = "0000"}

$model_file 		= $($scriptPath + "\DiskBenchmark_MSSQL_model.html")
$output_HTML_file 	= $($scriptPath + "\DiskBenchmark_MSSQL_output_$(hostname)_$timestamp.html")
$output_CSV_file 	= $($scriptPath + "\DiskBenchmark_MSSQL_output_$(hostname).csv")

if( -Not $csv_output){
	generate_HTML 
	start $output_HTML_file
}


## Compute number of CPU
$cpuCount=0
foreach($cpu in Get-WmiObject Win32_Processor -property NumberOfCores, NumberOfLogicalProcessors){
		$cpuCount += $cpu.NumberOfLogicalProcessors
}
if($cpuCount -le 4){ $cpuCount = 4 }
## Compute number of run and duration for each run
$nbr_run=3
$duration_run=20
if($duration -le 5){
	$nbr_run=3
	$duration_run=20
    $duration = 20
} else {
	$nbr_run = 5
	$duration_run = ($duration * 60 / 5 / 3 ) - 5
    $duration = $duration*60
}


### Simulate Data i/o : Read Ahead : 512K
$outstandings = 128 	# 128 = Standard Edition ; 5000 = Enterprise Edition
$threads = $cpuCount	# Depends of MAX Dop and Workload
$TestFilePath = "$Data_drive\diskspd_tmp.dat"
$DRA_param = "-c1G -d$duration_run -w0 -b512K -h -W -o$outstandings -t$threads -h -L $TestFilePath".Split()
$FuncDRA_param = "Function Read-Ahead parameters : $DRA_param"
benchmark $DRA_param ([ref]$Data_RunDetails) ([ref]$dataDRA_latency) ([ref]$dataDRA_iops) ([ref]$dataDRA_cores) "Data Read Ahead"
Remove-Item $TestFilePath

# Simulate Data i/o : Lazy Writer
$outstandings = 32		# 
$threads = 1 			# Equal number of NUMA nodes
$TestFilePath = "$Data_drive\diskspd_tmp.dat"
$DLW_param = "-c1G -d$duration_run -w100 -b64K -r -h -W -o$outstandings -t$threads -h -L $TestFilePath".Split()
$FuncDLW_param = "Function Lazy Writer parameters : $DLW_param"
benchmark $DLW_param ([ref]$Data_RunDetails) ([ref]$dataDLW_latency) ([ref]$dataDLW_iops) ([ref]$dataDLW_cores) "Data Lazy Writer"
Remove-Item $TestFilePath

# Simulate Log write :
$outstandings = 32		# max 116 outstandings
$threads = 1 			# Equal number of NUMA nodes (and max 4)
$TestFilePath = "$Log_drive\diskspd_tmp.dat"
$LRW_param = "-c1G -d$duration_run -w100 -b64K -h -W -o$outstandings -t$threads -h -L $TestFilePath".Split()
$FuncLRW_param = "Function Log Writer parameters : $LRW_param"
benchmark $LRW_param ([ref]$Data_RunDetails) ([ref]$dataLWR_latency) ([ref]$dataLWR_iops) ([ref]$dataLWR_cores) "Log Writer"
Remove-Item $TestFilePath

if ($to_the_limits_switch){
	$TestFilePath = "$Log_drive\diskspd_tmp.dat"
	benchmark_to_limits ([ref]$dataheatMap_data)
	Remove-Item $TestFilePath
}

if($csv_output){
	generate_CSV
} else { 
	# Stop HTML auto-refresh
	$refresh = ""
	generate_HTML
}

