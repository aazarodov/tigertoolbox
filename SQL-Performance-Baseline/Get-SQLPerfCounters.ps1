<# 
.SYNOPSIS  
    Collect performance counter statistics for SQL Server
.VERSION
    1.0    
.DESCRIPTION  
    Collects SQL performance data and stores metrics in local instance database for later extraction
.NOTES  
    Requires   : PowerShell V2+,.NET 2+, dependent on scripts Out-DataTable.ps1 and Write-DataTable.ps1
    
    This script uses the current user's credentials for authentication to the local SQL Server instance, so please ensure your Windows
    login has permissions to both the SQL instance and the Windows OS prior to script execution.
.EXAMPLE  
    Simple usage, using default mandatory parameters
    PS C:\foo> .\Get-SQLPerfCounters.ps1 -S 'SQLInstance' -D 'dba_local' -T 'PerformanceCounter'
     ----  
    server                    : SQLInstanceName
    destDatabase              : dba_local
    destDatabaseTable         : PerformanceCounter
    ---- 
.PARAMETER server
    Use physical name for standalone installs or virtual name for cluster installations.  If this is a named instance, add
    the instance name to this string (e.g. parikslaptop\test ).
.PARAMETER destDatabase
    Database name where PerformanceCounter table is located
.PARAMETER destDatabaseTable
    Table name where performance counter data is stored
#>
param (  
    [Parameter(Position=0, Mandatory=$true)]
    [Alias('S')]
    [ValidateLength(1, 50)]
    [string] $server,
    [Parameter(Position=1, Mandatory=$false)]
    [Alias('D')]
    [ValidateLength(1, 50)]
    [string]$destDatabase = "dba_local",
    [Parameter(Position=2, Mandatory=$false)]
    [Alias('T')]
    [ValidateLength(1, 50)]
    [string]$destDatabaseTable = "PerformanceCounter"
)

try{
 <#
  if(![System.Diagnostics.EventLog]::SourceExists("SQLPerfCounters"))
  {[System.Diagnostics.EventLog]::CreateEventSource("SQLPerfCounters","Application")}    
 #> 

    $scriptDir = Split-Path -parent $MyInvocation.MyCommand.Path
    $dt = $null
   
   .$scriptDir\Out-DataTable.ps1
   .$scriptDir\Write-DataTable.ps1
 
    $dbConn = New-Object Data.SqlClient.SqlConnection;
    $dbConn.ConnectionString = "Data Source=$server;Initial Catalog=dba_local;Integrated Security=True;"
    $dbConn.Open()

    $dbCmd = New-Object Data.SqlClient.SqlCommand "SELECT counter_name FROM PerformanceCounterList WHERE is_captured_ind = 1", $dbConn

    $dr = $dbCmd.ExecuteReader()

    [string[]]$perfList = @()

    if($dr.HasRows){
	   
       $server2 = $server -replace "\\.*$", ""
       $instance = $server.split('\')[1]

       if($instance -eq $null){$instance = 'SQLServer'}

       while ($dr.Read()){$perfList += $dr["counter_name"]}
        
       $gc = (get-counter -counter $perfList)
        
       foreach($g in $gc.CounterSamples){

	   $hProp = @{"CounterName" = $g.Path -replace ".*$instance\:|^`\`\`\`\$server2`\`\","";"CounterValue" = $g.CookedValue;"TimeStamp" = $g.TimeStamp}
           $ctr = New-Object -TypeName PSObject -Property $hProp | Select-Object CounterName, CounterValue, TimeStamp
           $dt += $ctr |  Out-DataTable
       }
        
       Write-DataTable  -ServerInstance $server -Database $destDatabase -TableName $destDatabaseTable -Data $dt -ErrorAction "Stop"
    }
}
catch{
    [string]$LogName = "Application"
	[string]$src = "SQLPerfCounters"
	$evnID = 10
	$errMssg = $_.Exception.GetBaseException().Message
	[string]$entryType = "Error"

	$errParms = @{'LogName'=$LogName;'Source'=$src;'EventID'=$evnID;'EntryType'=$entryType;'Message'=$errMssg}
	Write-Output @errParms
    $errMssg
    exit 1
}
finally{
    if($dr){$dr.Close()} 
    if($dbCmd){$dbCmd.Dispose()}
    if($dbConn){$dbConn.Close();$dbConn.Dispose()}
}


