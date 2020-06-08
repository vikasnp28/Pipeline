#! /opt/microsoft/powershell/6/pwsh
<#
    This script will pull a repository from a given GitHub URL and
    save locally to a specified folder. If a Release ID is specified,
    that particular release will be retrieved, otherwise it will be
    the latest release for the repo

    See https://developer.github.com/v3/repos/releases/
#>
param(
    [string] $GitRepo,
    [string] $ReleaseID = $null,
    [string] $GitHubAPIKey,
    [string] $TargetFolder
)

function CheckGithubRelease ($repo, $resource, $token)
{
    # Set up a token for authenticating to GitHub using HTTP Headers
    $headers = @{Authorization = 'Basic {0}' -f $token}

    # Set the URI to the API URL and required API resource
    $uri =  ($repo.Replace("github.dxc.com/","github.dxc.com/api/v3/repos/").Replace(".git","$($resource)"))

    try
    {
        $result = Invoke-RestMethod -Headers $headers -Uri $uri -Method "Get"

        return $result
    }
    catch
    {
        # Return null, calling function handles issues
        return $null
    }
}

######################################################################################
# Main
######################################################################################

try
{
    Write-Output "Start GitHub pull"

    # Enforce TLS 1.2 protocol which is required by some API calls
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;

    # Split the repo name from the repo organisation, eg "wm/Pipeline-Pilot":
    # wm = organisation
    # Pipeline-Pilot = repo
    $gitRepoShort = ($gitRepo -split '/')[-1]
    $gitHubURL = "https://github.dxc.com/$($GitRepo)/"

    # If a Release ID was supplied, get this particular release, otherwise get the latest
    if ($null -eq $ReleaseID)
    {
        $resource = "releases/latest"
    }
    else
    {
        $resource = "releases/tags/$($ReleaseID)"
    }

    # Define a token to connect to GitHub
    $token = [System.Convert]::ToBase64String([char[]]$GitHubApiKey)

    # Check this is a valid release in GitHub
    $gitRelease = CheckGithubRelease -repo $gitHubURL -resource $resource -token $token

    if ($gitRelease)
    {
        # This should be the same as the Release ID
        $tag = $gitRelease.tag_name
        Write-Output "Tag: $($tag) was found"
    }
    else
    {
        # A branch name was passed in for the Release ID. Typically used by development team
        $tag = $ReleaseID
        Write-Output "Branch: $($tag) was found"

    }
    $sourceURL = "https://github.dxc.com/$($GitRepo)/archive/$tag.zip"

    # Define the paths for the temporary zip file and the location
    # for the downloaded repository to be stored
    $targetPath = Join-Path $TargetFolder $gitRepoShort
    $targetPathZips = Join-Path $TargetFolder "Downloads"

    # Delete the target directory if it is already there
    if (Test-Path $targetPath)
    {
        Remove-Item -Path $TargetPath -Recurse -Force -ErrorAction Ignore
    }

    # Ensure the target path for zip file  exists
    if (!(Test-Path $targetPathZips))
    {
        New-Item -ItemType Directory -Force -Path $targetPathZips
    }

    Write-Output "Source is $($sourceURL)"
    Write-Output "Target Zips is $($targetPathZips)"
    Write-Output "Target folder for Repo is $($TargetPath)"

    $targetZip = Join-Path $targetPathZips "$($gitRepoShort).zip"

    # Set up a web client to download from GitHub
    $WC = New-Object System.Net.WebClient
    $WC.Headers.Add("Authorization", 'Basic {0}' -f $token)

    # Download the file
    $WC.DownloadFile($($sourceURL), $($targetZip))

    # Check download was successful
    $fileExists = Test-Path -Path $($targetZip) -PathType leaf
    if ($fileExists)
    {
        Write-Output "$($targetZip) was succesfully downloaded from GitHub."

        # Extract the zip file
        Expand-Archive -Path ($targetZip) -DestinationPath $TargetFolder -Force

        # Folder name defaults to the GitHub folder name with a tag appeneded, we need to rename this
        $tempFolder = Get-ChildItem $TargetFolder | Where-Object {$_.name -like "$($gitRepoShort)-*" -and $_.PSIsContainer} | ForEach-Object { $_.fullname }
        Rename-Item $tempFolder $targetPath
    }
    else
    {
        Write-Output "$($targetZip) was NOT succesfully downloaded from GitHub. Terminating...."
        exit 1
    }

    Write-Output "Completed GitHub pull"
}
catch [Exception]
{
    Write-output "PIPELINE-ERROR: Error has been raised/caught."
    Write-Output  $_.Exception.GetType().FullName, $_.Exception.Message
    Exit 1
}
