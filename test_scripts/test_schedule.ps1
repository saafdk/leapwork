# LEAPWORK REST API example: Run a schedule, iterate through the results and create bugs in TFS.# 
#
# Author: Claus Topholt.


# Function that finds a schedule in LEAPWORK based on a title, runs it and polls for the results.
function RunScheduleAndGetResults($schedule)
{
    Write-Host "Getting id for schedule '$schedule'."

    # Get the id of the schedule.
    $runScheduleId = "";
    $headers = @{}
    $headers.Add("AccessKey","bTyGAd0UGL70JFQg")
    $runSchedules = Invoke-WebRequest -ContentType "application/json" -Headers $headers "http://localhost:9001/api/v3/schedules" | ConvertFrom-Json
    foreach($runScheduleItem in $runSchedules)
    {
        if ($runScheduleItem.title -eq $schedule) { $runScheduleId = $runScheduleItem.id }
    }
    if ($runScheduleId -eq "") { throw "Could not find schedule '$schedule'." }

    Write-Host "Running the schedule."

    # Run the schedule now.
    $timestamp = [DateTime]::UtcNow.ToString("ddMMyyyy HHmmss")
    Start-Sleep 1
    $runNow = Invoke-WebRequest -Method PUT -ContentType "application/json" -Headers $headers "http://localhost:9001/api/v3/schedules/$runScheduleId/runNow"
    if ($runNow.StatusCode -ne 200) { throw "Could not run schedule." }
    $runNowResponse=$runNow.Content | ConvertFrom-Json
    $runId=$runNowResponse.RunId
    # Get the result, keep polling every 5 seconds until a new result is returned.
    do
    {
        Start-Sleep -Seconds 5

        Write-Host "Polling for run results."

        $runResult = Invoke-WebRequest -ContentType "application/json" -Headers $headers "http://localhost:9001/api/v3/run/$runId" | ConvertFrom-Json         

    } 
    while ($runResult.Status -ne 'Finished')

    Write-Host "Results received."

    return $runResult
}


# Function that creates a bug with a specific title in TFS or updates if it already exists.
function CreateOrUpdateBug($title, $description)
{
    # Create an authorization header using a Personal Access Token.
    $pat = "YOUR PERSONAL ACCESS TOKEN HERE"
    $patEncoded = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)"));
    $header = @{"Authorization" = "Basic $patEncoded"}

    # See if a bug with the same title already exists.
    $queryAlreadyExists = '{ "query": "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems ' +
                          'WHERE [System.WorkItemType] = ''Bug'' AND [System.Title] = ''' + $bugTitle + ''' AND [System.State] <> ''Removed'' ' + 
                          'ORDER BY [System.Id] DESC" }'
    $urlAlreadyExists = "https://YOURINSTANCE.visualstudio.com/DefaultCollection/YOURPROJECT/_apis/wit/wiql?api-version=1.0"
    $header['Content-Type'] = 'application/json'
    $resultAlreadyExists = Invoke-RestMethod -Headers $header -Method Post -Body $queryAlreadyExists $urlAlreadyExists

    # If the bug already exists, update it.
    if ($resultAlreadyExists.workItems.Count -gt 0)
    {
        Write-Host "Updating existing bug $($resultAlreadyExists.workItems[0].id)."

        # Add a note that this bug was updated or re-opened.
        $timestamp = [DateTime]::UtcNow.ToString("dd-MM-yyyy HH:mm:ss")
        $bugDescription = "Updated or re-opened by LEAPWORK on $timestamp.

" + $bugDescription

        # Update bug.
        $queryUpdateBug = '[ { "op" : "replace", "path" : "/fields/System.Title", "value" : "' + $bugTitle + '" }, ' +
        '{ "op" : "add", "path" : "/fields/Microsoft.VSTS.TCM.ReproSteps", "value" : "' + $bugDescription + '" }, ' + 
        '{ "op" : "replace", "path" : "/fields/System.State", "value" : "New" } ]'
        $urlUpdateBug = "https://YOURINSTANCE.visualstudio.com/DefaultCollection/_apis/wit/workitems/$($resultAlreadyExists.workItems[0].id)?api-version=1.0"
        $header['Content-Type'] = 'application/json-patch+json'
        $resultUpdateBug = Invoke-RestMethod -Headers $header -Method Patch -Body $queryUpdateBug $urlUpdateBug
    }
    else
    {
        Write-Host "Creating new bug."

        # Create new bug.
        $queryCreateNewBug = '[ { "op" : "add", "path" : "/fields/System.Title", "value" : "' + $bugTitle + '" }, ' +
        '{ "op" : "add", "path" : "/fields/Microsoft.VSTS.TCM.ReproSteps", "value" : "' + $bugDescription + '" }, ' + 
        '{ "op" : "add", "path" : "/fields/System.State", "value" : "New" } ]'
        $urlCreateNewBug = 'https://YOURINSTANCE.visualstudio.com/DefaultCollection/YOURPROJECT/_apis/wit/workitems/$Bug?api-version=1.0'
        $header['Content-Type'] = 'application/json-patch+json'
        $resultCreateNewBug = Invoke-RestMethod -Headers $header -Method Patch -Body $queryCreateNewBug $urlCreateNewBug
    }
}


# Run the LEAPWORK schedule "My Test Schedule" and get the results.
$runResult = RunScheduleAndGetResults("My Test Schedule")

# If there are any failed cases in the results, iterate through them.
if ($runResult.Failed -gt 0)
{
    Write-Host "Found $($runResult.Failed) failed case(s)."
    $headers = @{}
    $headers.Add("AccessKey","bTyGAd0UGL70JFQg")
    $runId=$runResult.RunId
    $runItemIds = Invoke-WebRequest -ContentType "application/json" -Headers $headers http://localhost:9001/api/v3/run/$runId/runItemIds | ConvertFrom-Json 

    $rootPath =$runResult.RunFolderPath
    foreach ($runItemId in $runItemIds.RunItemIds)
    {   
   
    $runItems = Invoke-WebRequest -ContentType "application/json" -Headers $headers http://localhost:9001/api/v3/runItems/$runItemId | ConvertFrom-Json 

        if($runItems.FlowInfo.Status -eq 'Failed')
        {

         # Create a title for the bug.
            $bugTitle = "LEAPWORK: " + $runItems.FlowInfo.FlowTitle

            # Create a description that contains the log messages.
            $newline = "\r\n";
           
            $keyFrames = Invoke-WebRequest -ContentType "application/json" -Headers $headers http://localhost:9001/api/v3/runItems/$runItemId/keyframes/1 | ConvertFrom-Json 

            $bugDescription = "Log from LEAPWORK:$newline $newline"
            foreach ($keyframe in $keyFrames)
            {
                if ($keyframe.Level -ge 1)
                {
                    $keyframeTimestamp = get-date($keyframe.Timestamp.LocalDateTime) -Format "dd-MM-yyyy HH:mm:ss"
                    $bugDescription += "$keyframeTimestamp - $($keyframe.LogMessage) $newline"
                }
            }

            # Add path to video and screenshots.
            $mediaPath = Join-Path -Path $rootPath  "$($runItems.RunItemId)"
            $videoPath = Join-Path -Path $mediaPath  "$($runItems.RunItemId).avi"
            $videoPath = $videoPath.Replace('\', '\\')
            $screenshotsPath = Join-Path -Path $mediaPath "Screenshots"
            $screenshotsPath = $screenshotsPath.Replace('\', '\\')
            $bugDescription += "$newline Video: $videoPath $newline"
            $bugDescription += "$newline Screenshots (if any): $screenshotsPath $newline"

           
            # Create or update bug in TFS.
            CreateOrUpdateBug($bugTitle, $bugDescription)
        }
    }

}
else
{
    Write-Host "No failed cases found."
}