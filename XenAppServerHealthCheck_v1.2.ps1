Param($silo,$offset,$country)
################################################################################################
## XenAppServerHealthCheck
## Original script by: Jason Poyner, jason.poyner@deptive.co.nz, techblog.deptive.co.nz
## Modified by: Bart Jacobs, bart@bj-it.be
## Changelog:
## v1.0 Inital release
## v1.1 Logging to CSV per server
## v1.2 Logging to CSV Total
################################################################################################
if ((Get-PSSnapin "Citrix.XenApp.Commands" -EA silentlycontinue) -eq $null) {
	try { Add-PSSnapin Citrix.XenApp.Commands -ErrorAction Stop }
	catch { write-error "Error loading XenApp Powershell snapin"; Return }
}

# Change the below variables to suit your environment
#==============================================================================================
# Default load evaluator assigned to servers. Can have multiple values in format "LE1", "LE2",
# if a match is made to ANY of the listed LEs SUCCESS is returned for the LE check.
$defaultLE       = "LE1"
 
# We always schedule reboots on XenApp farms, usually on a weekly basis. Set the maxUpTimeDays
# variable to the maximum number of days a XenApp server should be up for.
$maxUpTimeDays = 7

# Only change this if you have changed the Session Reliability port from the default of 2598
$sessionReliabilityPort = "2598"

# Silo Parameter
# The script is started with an identifier of the Silo of servers you are monitoring. This section parses that parameter and populates some variables accordingly
# More silo's -> More 
if ($silo -eq "PRD")
	{
	$serversilo = "SRVPRD*"
	$silotitle = "XenApp Producion Silo Citrix Dashboard"
	$siloerrortitle = "XenApp Production Silo Error Report"
	
	}

$resultfilename = "XA-"+$silo+"_Results.htm"
$errorfilename = "XA-"+$silo+"_Errors.htm"
$logfilename = 	"XA-"+$silo+"_Results_"+$offset+".log"


#==============================================================================================
 
$currentDir = Split-Path $MyInvocation.MyCommand.Path
$outputdir = "c:\Company"
$logfile    = Join-Path $outputDir $logfilename
$resultsHTM = Join-Path $outputDir $resultfilename
$errorsHTM  = Join-Path $outputDir $errorfilename
 
$headerNames  = "ActiveSessions", "ServerLoad", "Ping", "Logons", "LoadEvaluator", "ICAPort", "CGPPort", "IMA", "Spooler", "CitrixPrint", "WMI", "Uptime"
$headerWidths = "5",              "4",          "4",    "4",      "5",             "4",       "4",        "4",       "4" ,        "4",     "4",       "4"

#==============================================================================================
function LogMe() {
	Param(
		[parameter(Mandatory = $true, ValueFromPipeline = $true)] $logEntry,
		[switch]$display,
		[switch]$error,
		[switch]$warning,
		[switch]$progress
	)

	if ($error) {
		$logEntry = "[ERROR] $logEntry" ; Write-Host "$logEntry" -Foregroundcolor Red}
	elseif ($warning) {
		Write-Warning "$logEntry" ; $logEntry = "[WARNING] $logEntry"}
	elseif ($progress) {
		Write-Host "$logEntry" -Foregroundcolor Green}
	elseif ($display) {
		Write-Host "$logEntry" }
	 
	#$logEntry = ((Get-Date -uformat "%D %T") + " - " + $logEntry)
	$logEntry | Out-File $logFile -Append
}


#==============================================================================================
function Ping([string]$hostname, [int]$timeout = 1000, [int]$retries = 3) {
	$result = $true
	$ping = new-object System.Net.NetworkInformation.Ping #creates a ping object
	$i = 0
	do {
		$i++
		#write-host "Count: $i - Retries:$retries"
		
		try {
			#write-host "ping"
			$result = $ping.send($hostname, $timeout).Status.ToString()
		} catch {
			#Write-Host "error"
			continue
		}
		if ($result -eq "success") { return $true }
		
	} until ($i -eq $retries)
	return $false
}


#==============================================================================================
Function writeHtmlHeader
{
param($title, $fileName)
$date = ( Get-Date -format R)
$head = @"
<html>
<head>
<meta http-equiv='Content-Type' content='text/html; charset=iso-8859-1'>
<title>$title</title>
<STYLE TYPE="text/css">
<!--
td {
font-family: Tahoma;
font-size: 11px;
border-top: 1px solid #999999;
border-right: 1px solid #999999;
border-bottom: 1px solid #999999;
border-left: 1px solid #999999;
padding-top: 0px;
padding-right: 0px;
padding-bottom: 0px;
padding-left: 0px;
overflow: hidden;
}
body {
margin-left: 5px;
margin-top: 5px;
margin-right: 0px;
margin-bottom: 10px;
table {
table-layout:fixed; 
border: thin solid #000000;
}
-->
</style>
</head>
<body>
<table width='1200'>
<tr bgcolor='#CCCCCC'>
<td colspan='7' height='48' align='center' valign="middle">
<font face='tahoma' color='#003399' size='4'>
<!--<img src="http://servername/administration/icons/xenapp.png" height='42'/>-->
<! <strong>$title - $date</strong></font>
</td>
</tr>
</table>
<table width='1200'>
<tr bgcolor='#CCCCCC'>
<td width=50% height='48' align='center' valign="middle">
<font face='tahoma' color='#003399' size='4'>
<!--<img src="http://servername/administration/icons/active.png" height='32'/>-->
Active Sessions:  $TotalActiveSessions</font>
<td width=50% height='48' align='center' valign="middle">
<font face='tahoma' color='#003399' size='4'>
<!--<img src="http://servername/administration/icons/disconnected.png" height='32'/>-->
Disconnected Sessions:  $TotalDisconnectedSessions</font>
</td>
</tr>
</table>
"@
$head | Out-File $fileName
}

# ==============================================================================================
Function writeTableHeader
{
param($fileName)
$tableHeader = @"
<table width='1200'><tbody>
<tr bgcolor=#CCCCCC>
<td width='6%' align='center'><strong>ServerName</strong></td>
"@

$i = 0
while ($i -lt $headerNames.count) {
	$headerName = $headerNames[$i]
	$headerWidth = $headerWidths[$i]
	$tableHeader += "<td width='" + $headerWidth + "%' align='center'><strong>$headername</strong></td>"
	$i++
}

$tableHeader += "</tr>"

$tableHeader | Out-File $fileName -append
}

# ==============================================================================================
Function writeData
{
	param($data, $fileName)
	
	$data.Keys | sort | foreach {
		$tableEntry += "<tr>"
		$computerName = $_
		$tableEntry += ("<td bgcolor='#CCCCCC' align=center><font color='#003399'>$computerName</font></td>")
		#$data.$_.Keys | foreach {
		$headerNames | foreach {
			#"$computerName : $_" | LogMe -display
			try {
				if ($data.$computerName.$_[0] -eq "SUCCESS") { $bgcolor = "#387C44"; $fontColor = "#FFFFFF" }
				elseif ($data.$computerName.$_[0] -eq "WARNING") { $bgcolor = "#FF7700"; $fontColor = "#FFFFFF" }
				elseif ($data.$computerName.$_[0] -eq "ERROR") { $bgcolor = "#FF0000"; $fontColor = "#FFFFFF" }
				else { $bgcolor = "#CCCCCC"; $fontColor = "#003399" }
				$testResult = $data.$computerName.$_[1]
			}
			catch {
				$bgcolor = "#CCCCCC"; $fontColor = "#003399"
				$testResult = ""
			}
			
			$tableEntry += ("<td bgcolor='" + $bgcolor + "' align=center><font color='" + $fontColor + "'>$testResult</font></td>")
		}
		
		$tableEntry += "</tr>"
	}
	
	$tableEntry | Out-File $fileName -append
}

 
# ==============================================================================================
Function writeHtmlFooter
{
param($fileName)
@"
</table>
<table width='1200'>
<tr bgcolor='#CCCCCC'>
<td colspan='7' height='25' align='left'>
<font face='courier' color='#003399' size='2'><strong>Default Load Evaluator  = $DefaultLE</strong></font>
<tr bgcolor='#CCCCCC'>
<td colspan='7' height='25' align='left'>
<font face='courier' color='#003399' size='2'><strong>Default VDISK Image         = $DefaultVDISK</strong></font>
</td>
</tr>
</table>
</body>
</html>
"@ | Out-File $FileName -append
}

Function Check-Port  
{
	param ([string]$hostname, [string]$port)
	try {
		$socket = new-object System.Net.Sockets.TcpClient($hostname, $Port) #creates a socket connection to see if the port is open
	} catch {
		$socket = $null
		"Socket connection failed" | LogMe -display -error
		return $false
	}

	if($socket -ne $null) {
		"Socket Connection Successful" | LogMe
		
		if ($port -eq "1494") {
			$stream   = $socket.GetStream() #gets the output of the response
			$buffer   = new-object System.Byte[] 1024
			$encoding = new-object System.Text.AsciiEncoding

			Start-Sleep -Milliseconds 500 #records data for half a second			
		
			while($stream.DataAvailable)
			{
				$read     = $stream.Read($buffer, 0, 1024)  
				$response = $encoding.GetString($buffer, 0, $read)
				#Write-Host "Response: " + $response
				if($response -like '*ICA*'){
					"ICA protocol responded" | LogMe
					return $true
				} 
			}
			
			"ICA did not response correctly" | LogMe -display -error
			return $false
		} else {
			return $true
		}
	   
	} else { "Socket connection failed" | LogMe -display -error; return $false }
}

# ==============================================================================================
# ==                                       MAIN SCRIPT                                        ==
# ==============================================================================================
# Company Parameter
# The script is started with an identifier of the country/datacenter of servers you are monitoring. This section parses that parameter and populates some variables accordingly
# More silo's -> More 

if ($country -eq "BE")
	{
	$XAZDC = "XAZDP001"
    $datacenterloadlogfile = "Belgium-PRD.csv"
    
	}

if ($country -eq "NL")
	{
	$XAZDC = "XAZDP002"
    $datacenterloadlogfile = "Netherlands-PRD.csv"
    }

$datacenterloadlogfilepath = Join-Path $outputdir $datacenterloadlogfile
	
Set-XADefaultComputerName -Scope CurrentUser -ComputerName $XAZDC

# Script loop
# To run the script multiple times, an offset parameter was introduced. Depending on that parameter, the script loop waits for a number of seconds defined in this parameter.

while ($true) 
{
"Sleeping " + $offset + "s" | LogMe -display -progress
start-sleep -s $offset 

# Get Start Time
$startDTM = (Get-Date)

"Checking server health..." | LogMe -display
"Remove logfile..." | LogMe -display
rm $logfile -force -EA SilentlyContinue

# Data structure overview:
# Individual tests added to the tests hash table with the test name as the key and a two item array as the value.
# The array is called a testResult array where the first array item is the Status and the second array
# item is the Result. Valid values for the Status are: SUCCESS, WARNING, ERROR and $NULL.
# Each server that is tested is added to the allResults hash table with the computer name as the key and
# the tests hash table as the value.
# The following example retrieves the Logons status for server NZCTX01:
# $allResults.NZCTX01.Logons[0]

$allResults = @{}

# Get session list once to use throughout the script
"Get session list..." | LogMe -display
$sessions = Get-XASession | Where{$_.ServerName -like $serversilo}
"Get server list..." | LogMe -display 
Get-XAServer | Where{$_.ServerName -like $serversilo} | % {

	$tests = @{}	
	$server = $_.ServerName
	
	$server | LogMe -display -progress
	 
	# Check server logons
	if($_.LogOnsEnabled -eq $false){
		"Logons are disabled on this server" | LogMe -display -warning
		$tests.Logons = "WARNING", "Disabled"
	} else {
		$tests.Logons = "SUCCESS","Enabled"
	}
	
	# Report on active server sessions
	$activeServerSessions = [array]($sessions | ? {$_.State -eq "Active" -and $_.Protocol -eq "Ica" -and $_.ServerName -match $server})
	if ($activeServerSessions) { $totalActiveServerSessions = $activeServerSessions.count }
	# the  following line will return unique users rather than active sessions
	#if ($activeServerSessions) { $totalActiveServerSessions = ($activeServerSessions | Group-Object -property AccountName).count }
	else { $totalActiveServerSessions = 0 }
	if ($totalActiveServerSessions -eq 0)
		{
		$tests.ActiveSessions = "ERROR", $totalActiveServerSessions
		}
	else 
		{
		$tests.ActiveSessions = "SUCCESS", $totalActiveServerSessions
		}
		
	# Check Load Evaluator
	$assignedLE = (Get-XALoadEvaluator -ServerName $_.ServerName).LoadEvaluatorName
	if ($defaultLE -ne $assignedLE) 
        {
		"Non-default Load Evaluator assigned" | LogMe -display -warning
		$tests.LoadEvaluator = "WARNING", $assignedLE
	    } 
    else 
        {
		$tests.LoadEvaluator = "SUCCESS", $assignedLE
	    }

	# Ping server 
	$result = Ping $server 100
	if ($result -ne "SUCCESS") { $tests.Ping = "ERROR", $result }
	else { $tests.Ping = "SUCCESS", $result 
	
		# Test ICA connectivity
		if (Check-Port $server 1494) { $tests.ICAPort = "SUCCESS", "Success" }
		else { $tests.ICAPort = "ERROR","No response" }
		
		# Test Session Reliability port
		if (Check-Port $server $sessionReliabilityPort) { $tests.CGPPort = "SUCCESS", "Success" }
		else { $tests.CGPPort = "ERROR", "No response" }
		
		# Check services
		$services = Get-Service -Computer $Server
		if (($services | ? {$_.Name -eq "IMAService"}).Status -Match "Running") {
			"IMA service running..." | LogMe
			$tests.IMA = "SUCCESS", "Success"
		} else {
			"IMA service stopped"  | LogMe -display -error
			$tests.IMA = "ERROR", "Error"
		}
			
		if (($services | ? {$_.Name -eq "Spooler"}).Status -Match "Running") {
			"SPOOLER service running..." | LogMe
			$tests.Spooler = "SUCCESS","Success"
		} else {
			"SPOOLER service stopped"  | LogMe -display -error
			$tests.Spooler = "ERROR","Error"
		}
			
		if (($services | ? {$_.Name -eq "cpsvc"}).Status -Match "Running") {
			"Citrix Print Manager service running..." | LogMe
			$tests.CitrixPrint = "SUCCESS","Success"
		} else {
			"Citrix Print Manager service stopped"  | LogMe -display -error
			$tests.CitrixPrint = "ERROR","Error"
		}			
		
		$tests.XML = "SUCCESS","N/A"	
		
		# If the IMA service is running, check the server load
		if ($tests.IMA[0] -eq "Success") {
			try {
				$CurrentServerLoad = Get-XAServerLoad -ServerName $server
				$CtxServerLoad="$(($CurrentServerload.load)/100)%"
				
				#$CurrentServerLoad.GetType().Name|LogMe -display -warning
				if( [int] $CurrentServerLoad.load -lt 7500) {
					  "Serverload is low" | LogMe					  
					  $tests.Serverload = "SUCCESS", $CtxServerLoad
					}
				elseif([int] $CurrentServerLoad.load -lt 9000) {
					"Serverload is Medium" | LogMe -display -warning
					$tests.Serverload = "WARNING", $CtxServerLoad
				}   	
				else {
					"Serverload is High" | LogMe -display -error
					$tests.Serverload = "ERROR", $CtxServerLoad
				}   
			$serverloadlogfile = $server+".csv"
            $serverloadlogfilepath = Join-Path $outputdir $serverloadlogfile
            $datum = Get-Date -Format d
            $tijd = get-date -Format t
            $datumtijd = $datum +" "+ $tijd

            $csvContents = @() # Create the empty array that will eventually be the CSV file

            $row = New-Object System.Object # Create an object to append to the array
            $row | Add-Member -MemberType NoteProperty -Name "Date" -Value $datumtijd
            $row | Add-Member -MemberType NoteProperty -Name "ActiveSessions" -Value $totalActiveServerSessions
            $row | Add-Member -MemberType NoteProperty -Name "CitrixServerLoad" -Value $CtxServerLoad
            
            $csvContents += $row # append the new data to the array#
            $csvContents | Export-CSV -path $serverloadlogfilepath -append -NoTypeInformation

            if ($offset -eq 0)
            {
            $csvContents2 = @() # Create the empty array that will eventually be the CSV file

            $row2 = New-Object System.Object # Create an object to append to the array
            $row2 | Add-Member -MemberType NoteProperty -Name "Servername" -Value $server
            $row2 | Add-Member -MemberType NoteProperty -Name "Date" -Value $datumtijd
            $row2 | Add-Member -MemberType NoteProperty -Name "ActiveSessions" -Value $totalActiveServerSessions
            $row2 | Add-Member -MemberType NoteProperty -Name "CitrixServerLoad" -Value $CtxServerLoad
            
            $csvContents2 += $row2 # append the new data to the array#
            $csvContents2 | Export-CSV -path $datacenterloadlogfilepath -append -NoTypeInformation
            }

            }
			catch {
				"Error determining Serverload" | LogMe -display -error
				$tests.Serverload = "ERROR", $CtxServerLoad				
			}
			$CurrentServerLoad = 0
		}

		# Test WMI
		$tests.WMI = "ERROR","Error"
		try { $wmi=Get-WmiObject -class Win32_OperatingSystem -computer $_.ServerName } 
		catch {	$wmi = $null }

		# Perform WMI related checks
		if ($wmi -ne $null) {
			$tests.WMI = "SUCCESS", "Success"
			$LBTime=$wmi.ConvertToDateTime($wmi.Lastbootuptime)
			[TimeSpan]$uptime=New-TimeSpan $LBTime $(get-date)

			if ($uptime.days -gt $maxUpTimeDays){
				 "Server reboot warning, last reboot: {0:D}" -f $LBTime | LogMe -display -warning
				 $tests.Uptime = "WARNING", $uptime.days
			} else {
				 $tests.Uptime = "SUCCESS", $uptime.days
			}
			
		} else { "WMI connection failed - check WMI for corruption" | LogMe -display -error	}
	
	}

	$allResults.$server = $tests
}

# Get farm session info
$ActiveSessions       = [array]($sessions | ? {$_.State -eq "Active" -and $_.Protocol -eq "Ica"})
$DisconnectedSessions = [array]($sessions | ? {$_.State -eq "Disconnected" -and $_.Protocol -eq "Ica"})

if ($ActiveSessions) { $TotalActiveSessions = $ActiveSessions.count }
# the  following line will return unique users rather than active sessions
# if ($activeSessions) { $totalActiveSessions = ($activeSessions | Group-Object -property AccountName).count }
else { $TotalActiveSessions = 0 }

if ($DisconnectedSessions) { $TotalDisconnectedSessions = $DisconnectedSessions.count }
else { $TotalDisconnectedSessions = 0 }

"Total Active Sessions: $TotalActiveSessions" | LogMe -display
"Total Disconnected Sessions: $TotalDisconnectedSessions" | LogMe -display

# Write all results to an html file
Write-Host ("Saving results to html report: " + $resultsHTM)
writeHtmlHeader $silotitle $resultsHTM
writeTableHeader $resultsHTM
$allResults | sort-object -property FolderPath | % { writeData $allResults $resultsHTM }

# Get End Time
$endDTM = (Get-Date)

# Echo Time elapsed
"Elapsed Time: $(($endDTM-$startDTM).totalseconds) seconds"
}