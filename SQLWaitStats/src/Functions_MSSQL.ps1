## FUNCTIONS
#  . Test-IsAdmin 
#  . Get-MountPoint
#  . LoadModule
#
## CONSTANTS
#  . head_code = CSS + Javascript : toggle2(showHideDiv, switchTextDiv)
#  . end_code
#########################################################################################################
# History :
#  - 0.1 - 01/12/2014 : Creation
#  - 0.2 - 13/08/2015 : Add function 
#########################################################################################################

function Test-IsAdmin {
	([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
}

function get-ntfsinfo {
	param ([String[]]$drive = "C:\")

	$drive | foreach {
		if (test-path "$_") {
			  $cs = new-object PSObject
			  $cs | add-member NoteProperty Drive $_
			  $output = (fsutil fsinfo ntfsinfo "$_")
			  foreach ($line in $output) {
					$info = $line.split(':')
					#if the value is hex, convert to dec and put hex in ()
					if ($info[1].trim().startswith('0x0')) {
						  $info[1] = [Convert]::ToInt64(($info[1].Trim()),16).toString() + " (" + $info[1].Trim().toString() + ")"
					}
					$cs | add-member NoteProperty $info[0].trim().Replace(' ','_') $info[1].trim()
					$info = $null
			  }
			  $cs
		} else {
			  throw "Drive '$_' not found"
		}
	}
}

function get-mountPoint {
	param (  [String[]]$mountPoints = "c"
			,[String]$pathToFile = $(throw "Path to file required.") )
	
	foreach($point in $mountPoints)
	{
		if (! $point) { continue }
		if ( ${pathToFile}.StartsWith( ${point} ) ){
			Return $point
			break
		}
	}
}

#
# Loads the SQL Server Management Objects (SMO)
#

Function loadModule 
{
	## Import the SQL Server Module.
	if(-not(Get-Module -name "sqlps"))
	{
		if(Get-Module -ListAvailable | Where-Object { $_.name -eq "sqlps" })
		{
			#end if module available then import
			Import-Module -Name "sqlps" -DisableNameChecking
			Write-Host "Module sqlps imported..."
		} 
		else 
		{
			$ErrorActionPreference = "Stop"

			$sqlpsreg="HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.SqlServer.Management.PowerShell.sqlps"

			if (Get-ChildItem $sqlpsreg -ErrorAction "SilentlyContinue")
			{
				throw "SQL Server Provider for Windows PowerShell is not installed."
			}
			else
			{
				$item = Get-ItemProperty $sqlpsreg
				$sqlpsPath = [System.IO.Path]::GetDirectoryName($item.Path)
			}


			$assemblylist = 
			"Microsoft.SqlServer.Management.Common",
			"Microsoft.SqlServer.Smo",
			"Microsoft.SqlServer.Dmf ",
			"Microsoft.SqlServer.Instapi ",
			"Microsoft.SqlServer.SqlWmiManagement ",
			"Microsoft.SqlServer.ConnectionInfo ",
			"Microsoft.SqlServer.SmoExtended ",
			"Microsoft.SqlServer.SqlTDiagM ",
			"Microsoft.SqlServer.SString ",
			"Microsoft.SqlServer.Management.RegisteredServers ",
			"Microsoft.SqlServer.Management.Sdk.Sfc ",
			"Microsoft.SqlServer.SqlEnum ",
			"Microsoft.SqlServer.RegSvrEnum ",
			"Microsoft.SqlServer.WmiEnum ",
			"Microsoft.SqlServer.ServiceBrokerEnum ",
			"Microsoft.SqlServer.ConnectionInfoExtended ",
			"Microsoft.SqlServer.Management.Collector ",
			"Microsoft.SqlServer.Management.CollectorEnum",
			"Microsoft.SqlServer.Management.Dac",
			"Microsoft.SqlServer.Management.DacEnum",
			"Microsoft.SqlServer.Management.Utility"


			foreach ($asm in $assemblylist)
			{
				$asm = [Reflection.Assembly]::LoadWithPartialName($asm)
			}

			Push-Location
			cd $sqlpsPath
			update-FormatData -prependpath SQLProvider.Format.ps1xml -ErrorAction SilentlyContinue
			Pop-Location
			Write-Host "sqlps assemblies loaded..."
		}
	}
}

# PowerShell v2.0 compatible version of [string]::IsNullOrWhitespace.
function StringIsNullOrWhitespace([string] $string)
{
	if ($PSVersionTable.PSVersion.Major -gt 2)
	{
		#PS 3 or more
		return [string]::IsNullOrWhiteSpace($string)
	}
	else
	{
		#PS 2
		if ($string -ne $null) { $string = $string.Trim() }
		return [string]::IsNullOrEmpty($string)
	}
	return $false
}

## Constants
$head_code = "
<style>
h2 {
  color:#D5DDE5;;
  background:#1b1e24;
  border-top:4px solid #9ea7af;
  border-bottom:4px solid #9ea7af;
  /*font-size:1.2em;*/
  /*font-weight: 100;*/
  padding:1em;
  text-align:left;
  /*vertical-align:middle;*/
}
h3 {
  /*color:#D5DDE5;;
  background:#1b1e24;
  border-top:4px solid #9ea7af;
  border-bottom:4px solid #9ea7af;*/
  /*font-size:1.2em;*/
  /*font-weight: 100;*/
  padding:1em;
  text-align:left;
  text-decoration:underline;
  -moz-text-decoration-color: #9ea7af;
  text-decoration-color: #9ea7af;
  /*vertical-align:middle;*/
}
table {
  background: white;
  border-radius:3px;
  border-Hide details: Hide details;
  /*height: 320px;*/
  margin: auto;
  /*max-width: 600px;*/
  padding:5px;
  width: 100%;
  box-shadow: 0 5px 10px rgba(0, 0, 0, 0.1);
  animation: float 5s infinite;
  text-align: left;
}
th {
  color:#D5DDE5;;
  background:#1b1e24;
  border-bottom:4px solid #9ea7af;
  border-right: 1px solid #343a45;
  font-size:1.2em;
  font-weight: 100;
  padding:0.6em;
  text-align:left;
  vertical-align:middle;
}
tr {
  border-top: 1px solid #C1C3D1;
  border-bottom-: 1px solid #C1C3D1;
  color:#666B85;
  /*font-size:16px;*/
  font-size:1em;
  font-weight:normal;
  /*text-shadow: 0 1px 1px rgba(256, 256, 256, 0.1);*/
}
tr:hover td {
  background:#4E5066;
  color:#FFFFFF;
}
tr:first-child {
  border-top:none;
}
tr:last-child {
  border-bottom:none;
}
tr:nth-child(odd) td {
  background:#EBEBEB;
}
tr:nth-child(odd):hover td {
  background:#4E5066;
}
tr:last-child td:first-child {
  border-bottom-left-radius:3px;
}
tr:last-child td:last-child {
  border-bottom-right-radius:3px;
}
td {
  background:#FFFFFF;
  /*padding:20px;*/
  padding:0.2em;
  text-align:left;
  vertical-align:middle;
  font-weight:300;
  /*font-size:18px;*/
  font-size:1em;
  /*text-shadow: -1px -1px 1px rgba(0, 0, 0, 0.1);*/
  border-right: 1px solid #C1C3D1;
}
</style>
<script language='javascript'> 
function toggle2(showHideDiv, switchTextDiv) {
	var ele = document.getElementById(showHideDiv);
	var text = document.getElementById(switchTextDiv);
	if(ele.style.display == 'block') {
    		ele.style.display = 'none';
		text.innerHTML = 'View details';
  	}
	else {
		ele.style.display = 'block';
		text.innerHTML = 'Hide details';
	}
}
</script>
"

$end_code ="
<script language='javascript'> 
var cells = document.getElementsByTagName(`"td`");
for (var i = 0; i < cells.length; i++) {
    if (cells[i].innerHTML == `"Failed`") {
        cells[i].style.backgroundColor = `"lightcoral`";
    }
}
</script>
"