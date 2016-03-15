
function resample-perfmon {
    param ([String]$file_path = $(throw "Path to file required."))
    
    $AllSamples     = Import-Counter -path $file_path
    $firstTimestamp = $AllSamples[0].Timestamp
    $lastTimestamp            = $AllSamples[-1].Timestamp
    
    Write-Output "PerfMon counters from : $firstTimestamp to $lastTimestamp"
    
    $current1Minute = $firstTimestamp.Minute
    $current5Minute = (($aSample.Timestamp).Minute - ($aSample.Timestamp).Minute % 5)
    
    $current1MinuteTimestamp = $firstTimestamp
    $current5MinuteTimestamp = $firstTimestamp
    
    $1MinuteSampling = @()
    $5MinuteSampling = @()
    
    $same1minute = @()
    $same5minute = @()
    
    foreach ($aSample in $AllSamples){
        if (($aSample.Timestamp).Minute -eq ($current1MinuteTimestamp).Minute)
        {
            # Sample in same minute
            $same1minute += $aSample.countersamples | select Path,CookedValue
            # Sample in same 5mn interval
            $same5minute += $aSample.countersamples | select Path,CookedValue
        }
        else
        {
            # Sample in another minute
            
            # Compute Averages
            $a1MinuteSample =@{}
            $same1minute | Group-Object -Property Path | %{
                $a1MinuteSample += @{ $_.Name =($_.Group | Measure-Object CookedValue -Average).Average }
            }
            $a1MinuteSample += @{ Timestamp = $current1MinuteTimestamp }
            
            $1MinuteSampling += New-Object PSObject -Property $a1MinuteSample;
            
            # Changes current minute
            $current1Minute = ($aSample.Timestamp).Minute
            $current1MinuteTimestamp = ($aSample.Timestamp)
            $same1minute = @()
            
            # Add current sample to just created minute collection
            $same1minute += $aSample.countersamples | select Path,CookedValue
            
            # Is a new 5mn change ?
            if ( (($aSample.Timestamp).Minute - ($aSample.Timestamp).Minute % 5) -eq ($current5MinuteTimestamp).Minute)
            {
                # Sample in same 5mn interval
                $same5minute += $aSample.countersamples | select Path,CookedValue
            }
            else
            {
                # New 5mn sample interval
                Write-Output "Compute $($current1MinuteTimestamp.ToString('dd/MM/yyyy HH:mm'))"
                # Compute Averages
                $a5MinuteSample =@{}
                $same5minute | Group-Object -Property Path | %{
                    $a5MinuteSample += @{ $_.Name =($_.Group | Measure-Object CookedValue -Average).Average }
                }
                $a5MinuteSample += @{ Timestamp = $current1MinuteTimestamp }
                
                $5MinuteSampling += New-Object PSObject -Property $a5MinuteSample;
                
                
                # Changes current 5 minute
                $current5Minute = (($aSample.Timestamp).Minute - ($aSample.Timestamp).Minute % 5)
                $current5MinuteTimestamp = ($aSample.Timestamp)
                $same5minute = @()
                
                # Add current sample to just created minute collection
                $same5minute += $aSample.countersamples | select Path,CookedValue
            }
        }
    }
    # Compute last 1m and 5m sample
    Write-Output "Compute $($current1MinuteTimestamp.ToString('dd/MM/yyyy HH:mm'))"
    
    # Compute Averages for last minute
    $a1MinuteSample =@{}
    $same1minute | Group-Object -Property Path | %{
        $a1MinuteSample += @{ $_.Name =($_.Group | Measure-Object CookedValue -Average).Average }
    }
    $a1MinuteSample += @{ Timestamp = $current1MinuteTimestamp }
    $1MinuteSampling += New-Object PSObject -Property $a1MinuteSample;
    
    # Compute Averages for last 5 minutes                           
    $a5MinuteSample =@{}
    $same5minute | Group-Object -Property Path | %{
        $a5MinuteSample += @{ $_.Name =($_.Group | Measure-Object CookedValue -Average).Average }
    }
    $a5MinuteSample += @{ Timestamp = $current1MinuteTimestamp }
    $5MinuteSampling += New-Object PSObject -Property $a5MinuteSample;
    
    #Write-Output $5MinuteSampling
    $fileDir = split-path $file_path
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file_path)
    Write-output "Write averages CSV to $($fileDir)"
    
    $1MinuteSampling | Export-Csv -path "$($fileDir)\$($fileName.Trim())_1mn.csv" -NoTypeInformation
    $5MinuteSampling | Export-Csv -path "$($fileDir)\$($fileName.Trim())_5mn.csv" -NoTypeInformation
}
