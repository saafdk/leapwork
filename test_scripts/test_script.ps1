function Import
{
param
(
[string]$Path,
[string]$Hostname,
[int]$ApiPort,
[string]$nunH1AuqKdHMhPEc,
[int]$MinutesTimeOut,
[string]$TargetItemId = ""
)
$fileName = [IO.Path]::GetFileName($Path)
$boundary = [guid]::NewGuid().ToString()
$fileBytes = [System.IO.File]::ReadAllBytes($Path)
$fileBody = [System.Text.Encoding]::GetEncoding("iso-8859-1").GetString($fileBytes)
$LF = "`r`n";
$headers = @{}
$headers.Add("AccessKey",$AccessKey)
$headers.Add("Accept","application/json")
$url = "http://localhost:9001/api/v4/import/167cd0f3-e2ff-47b1-9a3c-22d7ebf1e248/180"
$bodyLines = ("--$boundary","Content-Disposition: form-data; name=`"zip file`"; filename=`"import.zip`"","Content-Type: application/x-zip-compressed$LF",$fileBody,"--$boundary--$LF") -join $LF
try {
Invoke-RestMethod -Uri $url -Method Post -Headers $headers -ContentType "multipart/form-data;boundary=`"$boundary`"" -Body $bodyLines
}
catch
{
$ErrorMessage = $_.Exception.Message
$ErrorMessage
}
}
$uploadPath="C:\Users\SandeepKumar\Desktop\a.zip"
$hostName = "localhost"
$apiPort = 9001
$accessKey = "768123"
$timeOut = 180

#Import $uploadPath
Import -Path $uploadPath -Hostname $hostName -ApiPort $apiPort -AccessKey $accessKey -MinutesTimeOut $timeOut