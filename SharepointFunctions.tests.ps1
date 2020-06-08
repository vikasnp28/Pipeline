<#====================================================================================================================================================
GENERAL INFO
Copyright (c) 2018 DXC MWS Workplace Development Studio
All rights reserved.

OWNER           : DXC MWS Workplace Development Studio
AUTHOR          : dil-broker\x-ajanusauskas

REVISION HISTORY:
   2018 12 10- dil-broker\x-ajanusauskas - Initial version.

TECHNICAL OVERVIEW:
  Pester test for SharepointFunctions.ps1
  Attention this pester test does not use mocking, runs real actions by  rest api calls to SharePoint.
  For test list creation and cleanup the same functions, which are tested, are used. So if some ShPo function does not work,
  the SharePoint test environment prepare and cleanup also may not work!
  Because of this, when testing, if test failed, please pay attention to BeforeEach; GeforeAll; AfterEach; AfterAll blocks, verify if they work,
  they also might be a root cause of the test itself not finished as expected.


TECHNICAL REQUIREMENTS:
  PowerShell version: 5.0 5.1
  SharePoint:
    SharePint 2013 working site, accessible from session You are running test.
    the address to site, meant for testing, must be assigned to variable: $fSiteURLGood. While doing tests List: 'TestList' will be created in site. Delete this list manually after tests.
	Pester module installed. (initial version tested with:  Pester 4.4.2 )
      to install run as addmin: install-Module -Name Pester
Input-Requirements:
  specify value for SharePoint site $fSiteURLGood

Output
  if test is run as it is without any parameters, it will output Pester test result to console.

#>
param(
    [switch]$automated,
	  [string]$configRepoScriptPath,
    [string]$resourceDomainAdminUsername,
    [string]$resourceDomainAdminPwd,
    [string]$masterDomainAdminUsername,
    [string]$masterDomainAdminPwd
)

if ($automated -eq $true) {
  # load config repository script
	Set-Location (Split-Path $configRepoScriptPath -Parent)
  . "$configRepoScriptPath"

  $fSiteURLGood = 'http://' + (Get-RepositoryConcatenatedValue "spt_vm_name_prefix") + '001:80'
}
else {
  Clear-Host
  # moved this to manual section as it causes problems for automation
  Get-Module | Remove-Module # Remove old modules

	$fSiteURLGood ='http://dxcwldspdil01v:43254'
	# It is assumed that whoever runs this script, has implicit
	# login rights to the site. If that is not the case
	# we need to include credentials in this Pester script
	# (not done yet, takes quite some effort
}

$fSiteURLBad='http://IamNotResponding/toYou'
$fListNameNew = 'TestList'
$fListLookup = 'TestLookUp'

#region LoadScript
# load the script file into memory
# attention: make sure the script only contains function definitions
# and no active code. The entire script will be executed to load
# all functions into memory
# Pester script should be in same folder are below target script/library

Import-module "$PSScriptRoot\SharepointFunctions.psm1" -Verbose
#endregion

#Region Sharepoint Connectivity Check

Function Check-SPConnectivity {
# Script snippet to test Sharepoint Site availability over the network
# In the pipeline we cannot use remote Powershell, so we need to perform (IP) port
# targeted actions and see what comes back
Clear-Host 
$ErrorActionPreference = 'Stop'   # DO NOT REMOVE THIS STATEMENT, the script will not give proper results when removed.


# Following variables MUST come from the pipeline variables and MUST be the EXACT SAME
# values as used in the Pester Sharepoint REST calls. (Please note that
# the SERVERNAME only must be used, not the full URL).
$ServerName = 'swawldspt001' # Name of server, without the http(s):// prefix
$ServerPort = '80' # port used to publish the Sharepoint Site
# Do not change anything below this line.
:DoTheShPoTest Do {

      $ErrorDetected = $false
    $Results = @()

      # See if the machine name can be resolved to IP address
      $Results += $Doing = "Trying to resolve the computername $ServerName"
      Try {
            $ServerIPInfo = Resolve-DNSName $ServerName
      }
      Catch {
            $ErrorDetected = $True
            $ErrorObject = $_
            Break DoTheShPoTest
      }
    $Results += "Resolved $serverName to following:"
    $Results += $ServerIPInfo
    $Results += ("=" * 75)

      # Test if the TCP port is open. Use the actual servername to get a response from Sharepoint, not default IIS website
      $Results += $Doing = "Trying to see if port $ServerPort is open for $ServerName"
      Try {
      $Connection = Test-NetConnection $ServerName  -port $ServerPort
      }
      Catch {
            $ErrorDetected = $True
            $ErrorObject = $_
            Break DoTheShPoTest
      }

      If ($Connection.TcpTestSucceeded -ne $true) {
            $ErrorDetected = $True
            $ErrorObject = "" | Select "Test", "Result"
            $ErrorObject.Test = "Test-NetConnection"
            $ErrorObject.Result = "Connection test was NEGATIVE, port was not found open"
            Break DoTheShPoTest
      }
    $Results += "The connection to port $ServerPort of Server $serverName resulted in:"
    $Results += $Connection
    $Results += ("=" * 75)

      
    # See if we can capture a webpage
    $Results += $Doing = "Trying to retrieve a webpage from port $ServerPort of server $ServerName"
        Try {
        $WebPage = curl "http://$($ServerName):$ServerPort"
            # If we get here, the curl resulted in success, meaning that we:
            # - Have access to the website that is exposed at port 80
            # - Web content is displayed and captured in $webpage
    }
      Catch {
            # Default page at port 80 does not return anything valid. Lets see if
            # there is a Sharepoint site exposed
            Try {
            $WebPage = curl "http://$($ServerName):$ServerPort/_layouts/15/start.aspx#/default.aspx"
        }
            Catch {
                 $ErrorDetected = $True
                  $ErrorObject = $_
                  Break DoTheShPoTest
            }
      }
      # At this point we should have a webpage content
    if (($WebPage.Images).src -eq "iisstart.png") {
        # Default IIS page is presented, NOT sharepoint. This is a misconfiguration in IIS bindings
            $ErrorDetected = $True
            $ErrorObject = "" | Select "Test", "Result"
            $ErrorObject.Test = "Validate Webpage Content (curl)"
            $ErrorObject.Result = "Found the default IIS page on port $ServerPort exposed by server $ServerName"
            Break DoTheShPoTest
    }
    Elseif ($WebPage.Content -like '*content="Microsoft SharePoint"*' ) {
        $REsults += "Found proof that the webpage is from a Sharepoint published website"
        $Results += ("=" * 75)
      }
      Else {
        # Found something other than default IIS. Sharepoint?
      $ErrorDetected = $True
            $ErrorObject = "" | Select "Test", "Result", "Details"
            $ErrorObject.Test = "Get Webpage Content (curl)"
            $ErrorObject.Result = "Found unknown page on port 80 on port $ServerPort exposed by server $ServerName"
            $ErrorObject.Details = $WebPage
            Break DoTheShPoTest
    }
      # All tests passed
      Break DoTheShPoTest
} While ($true)

$ResultsJson = $Results | ConvertTo-Json
Write-Host $ResultsJson


if ($ErrorDetected) {
      $ErrorMessage = "ERROR: Issue found when $Doing"
      $ErrorObjectJson = $ErrorObject | ConvertTo-Json
      
      # Change to WRITE TO LOGFILE
      Write-Host $ErrorMessage
      Write-Host "Error object that was captured:"
      Write-Host $ErrorObjectJson
} Else {
    Write-Host "All Sharepoint Pre-Pester tests resulted in SUCCESS"
}
}  #End function
$CallSPCheckFunctionFirstTime =  Check-SPConnectivity
Start-Sleep -Seconds 300

$CallSPCheckFunctionFirstTime =  Check-SPConnectivity 

#EndRegion Sharepoint Connectivity Check


#list -----------------------------------------------------------
# describes the function Add-ShPoList
Describe 'Add-ShPoList' {

  BeforeEach { try {Remove-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew -ErrorAction SilentlyContinue
  					Remove-ShPoList -fSiteURL $fSiteURLGood -fListName $fListLookup -ErrorAction SilentlyContinue} catch{}  }

  # scenario 1: Unhappy path
  Context 'Running obvious unhappy paths'    {
    # test 1: throw an exception if no parameters are set:
    It 'throw an exception if no parameters are set' {
      { Add-ShPoList } | Should  Throw
    }
    # test 2: incorrect  fSiteURL
    It 'throw an exception if incorrect  fSiteURL' {
       {Add-ShPoList -fSiteURL $fSiteURLBad -fListName 'Strange_ShouldNotBeHere'} |  Should  Throw
    }
  }
  Context 'Running obvious happy paths with no credentials specified.' {
    it 'Create the List with name and description provided.' {
      $item =Add-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListDescription 'here is description.'
      $item.Title | Should Be $fListNameNew
      $item.Description | Should Be 'here is description.'
    }
     it 'Create the List with name and description and QuickLaunchParent ''TestQuickL''.' {
      $item = Add-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListDescription 'here is description.' -fListQuickLaunchParent 'TestQuickL'
      $item.Title | Should Be $fListNameNew
      $item.Description | Should Be 'here is description.'
    }

  }
}
# describes the function Add-ShPoList
Describe 'remove-ShPoList' {

  BeforeEach { try {Add-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{}  }

  # scenario 1: Unhappy path
  Context 'Running obvious unhappy paths'    {
    # test 1: throw an exception if no parameters are set:
    It 'throw an exception if no parameters are set' {
      {remove-ShPoList } | Should  Throw
    }
    # test 2: incorrect  fSiteURL
    It 'throw an exception if incorrect  fSiteURL' {
       {remove-ShPoList -fSiteURL $fSiteURLBad -fListName 'Strange_ShouldNotBeHere'} |  Should  Throw
    }
  }
  Context 'Running obvious happy paths with no credentials specified.' {
    # test 1
    it "Remove the List $fListNameNew" {
      {$result =remove-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew} | should not throw
      {Get-ShPoList  -fSiteURL $fSiteURLGood -fListName $fListNameNew } | should throw
    }
    # test 2 test no value returned
    it "Remove the List $fListNameNew" {
      remove-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew | should be $null
    }
  }
}
# describes the function Get-ShPoList
Describe 'Get-ShPoList' {

   BeforeEach { try {Add-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{}  }

  # scenario 1: Unhappy path
  Context 'Running obvious unhappy paths'    {
    # test 1: throw an exception if no parameters are set:
    It 'throw an exception if no parameters are set' {
      {Get-ShPoList} | Should  Throw
    }
    # test 2: incorrect  fSiteURL
    It 'throw an exception if incorrect  fSiteURL' {
       {Get-ShPoList -fSiteURL $fSiteURLBad -fListName 'Strange_ShouldNotBeHere'} |  Should  Throw
    }

    # test3 : incorrect  list provided.
    It 'throw an exception if non existing List provided.' {
       {Get-ShPoList -fSiteURL $fSiteURLBad -fListName 'Strange_ShouldNotBeHere'} |  Should  Throw
    }


  }
  Context 'Running obvious happy paths with no credentials specified.' {
    #test1
    it "Get the List $fListNameNew" {
      $result =get-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew
      $result.Title | should be $fListNameNew
      $result.ID | should not be $null

    }
    #test2
    it "Get the List $fListNameNew with all properties, switch -fFull" {
      $result =get-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew -fFull
      $result.Title | should be $fListNameNew
      $result.ID | should not be $null
      ($result | Get-Member ).count | should BeGreaterThan 23
    }

  }
}
# describes the function Update-ShPoList
Describe 'Update-ShPoList' {


  BeforeEach { try {Add-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{}  }

  # scenario 1: Unhappy path
  Context 'Running obvious unhappy paths'    {
    # test 1: throw an exception if no parameters are set:
    It 'throw an exception if no parameters are set' {
      {update-ShPoList } | Should  Throw
    }
    # test 2: incorrect  fSiteURL
    It 'throw an exception if incorrect  fSiteURL' {
       {update-ShPoList -fSiteURL $fSiteURLBad -fListName 'Strange_ShouldNotBeHere'} |  Should  Throw
    }

    # test3 : incorrect  list sprovided.
    It 'throw an exception if non existing List provided.' {
       {update-ShPoList -fSiteURL $fSiteURLGood -fListName 'Strange_ShouldNotBeHere'} |  Should  Throw
    }


  }
  Context 'Running obvious happy paths with no credentials specified.' {
    #test1 update description
    it "Update the List $fListNameNew description." {
      $result =update-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListDescription 'Updated'
      $result.description | should be 'Updated'
      (Get-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew).description | should be 'Updated'
    }
  }
}


#list item ------------------------------------------------------
# describes the function Add-ShPoListItem
Describe 'Add-ShPoListItem' {
  BeforeEach { try {Add-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{}  }

  BeforeAll {
    $fieldTitle = "my name is Waldo"
    $fields = @{  'Title'= $fieldTitle   }
  }
  # scenario 1: Unhappy path
  Context 'Running obvious unhappy paths'    {
    # test 1: throw an exception if no parameters are set:
    It 'throw an exception if no parameters are set' {
      {Add-ShPoListItem } | Should  Throw
    }
    # test 2: incorrect  fSiteURL
    It 'throw an exception if incorrect  fSiteURL' {
       {Add-ShPoListItem -fSiteURL $fSiteURLBad -fListName 'Strange_ShouldNotBeHere' -fListFields $fields} |  Should  Throw
    }

    # test3 : incorrect  list provided.
    It 'throw an exception if non existing List provided.' {
       {Add-ShPoListItem -fSiteURL $fSiteURLGood -fListName 'Strange_ShouldNotBeHere' -fListFields $fields } |  Should  Throw
    }


  }
  # scenario 2: Happy
  Context 'Running happy paths with no credentials specified.' {
    #test1 update description
    it "Add item to list '$fListNameNew' " {
      $result = Add-ShPoListItem -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListFields $fields
      $result.Title | should be $fieldTitle
    }
  }
}
# describes the function Get-ShPoListItems
Describe 'Get-ShPoListItem' {

  # create some items in the list
  BeforeAll {
    try {remove-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{}
    try {Add-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{}
    1..10 | ForEach-Object {@{ 'Title'= "Waldo_$($_)"  }} |
    ForEach-Object { Add-ShPoListItem -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListFields $_ }

  }
  AfterAll {
     try {remove-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{}
  }
  # scenario 1: Unhappy path
  Context 'Running obvious unhappy paths'    {
    # test 1: throw an exception if no parameters are set:
    It 'throw an exception if no parameters are set' {
      {get-ShPoListItems } | Should  Throw
    }
    # test 2: incorrect  fSiteURL
    It 'throw an exception if incorrect  fSiteURL' {
       {Get-ShPoListItem -fSiteURL $fSiteURLBad -fListName 'Strange_ShouldNotBeHere'  } |  Should  Throw
    }
     # test3 : incorrect  list provided.
    It 'throw an exception if non existing List provided.' {
       {Get-ShPoListItem -fSiteURL $fSiteURLGood -fListName 'Strange_ShouldNotBeHere' -fMaxNumber 2 } |  Should  Throw
    }


  }
  Context 'Running happy paths with no credentials specified.' {
    #test 1 get all items from list, no filter specified.
    it "Get All items in '$fListNameNew' " {
      $result = Get-ShPoListItem -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListFields *
      $result.count | should be 10
      ($result[0]|Get-Member).count | should BeGreaterThan 20 # check that filed count
    }
    #test 2 get item using filter
    it "get item using filter for Title from list '$fListNameNew'  " {
     {Get-ShPoListItem -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListFields * -fFilter "ID eq 5"} | should not throw

    }
    #test 3 get items without the filter but max 5
    it "get items without the filter but max 5'  " {
     (Get-ShPoListItem -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListFields * -fMaxNumber 5).count | should be 5

    }

  }
}
# describes the function Update-ShPoListItem
Describe 'Update-ShPoListItem' {
  # create some items in the list
  BeforeAll {
    try {remove-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{}
    try {Add-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{}
    $items= 1..10 | ForEach-Object {@{ 'Title'= "Waldo_$($_)"  }} |
    ForEach-Object { Add-ShPoListItem -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListFields $_ }
    $itemsIds = $items.Id


  }
   Context 'Running obvious unhappy paths'    {
     # test 1: throw an exception if no parameters are set:
      It 'throw an exception if no parameters are set' {
        {Update-ShPoListItem } | Should  Throw
      }
     # test 2: incorrect  fSiteURL
      It 'throw an exception if incorrect  fSiteURL' {
         {Update-ShPoListItem -fSiteURL $fSiteURLBad -fListName 'Strange_ShouldNotBeHere'  } |  Should  Throw
      }
     # test3 : incorrect  list provided.
      It 'throw an exception if non existing List provided.' {
         {Update-ShPoListItem -fSiteURL $fSiteURLGood -fListName 'Strange_ShouldNotBeHere' -fListFields @{Id=$itemsIds[0]; Title = 'Updated'} } |  Should  Throw
      }
    }
   Context 'Running happy paths with no credentials specified.' {
   #test 1 update items Title.
     it "Update item Title to 'Updated' with id $($itemsIds[1]) in '$fListNameNew' " {
        $result = Update-ShPoListItem -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListFields @{Id=$itemsIds[1]; Title = 'Updated'}
        $result.Title | should be 'Updated'
     }
   }

}
# describes the function Remove-ShPoListItem
Describe 'Remove-ShPoListItem' {
  # create some items in the list
  BeforeAll {
    try {remove-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{}
    try {Add-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{}
    $items= 1..10 | ForEach-Object {@{ 'Title'= "Waldo_$($_)"  }} |
    ForEach-Object { Add-ShPoListItem -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListFields $_ }
    $itemsIds = $items.Id
   }
  AfterAll{try {remove-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{} }
  Context 'Running obvious unhappy paths'    {
     # test 1: throw an exception if no parameters are set:
      It 'throw an exception if no parameters are set' {
        {Remove-ShPoListItem } | Should  Throw
      }
     # test 2: incorrect  fSiteURL
      It 'throw an exception if incorrect  fSiteURL' {
         {Remove-ShPoListItem -fSiteURL $fSiteURLBad -fListName 'Strange_ShouldNotBeHere'  } |  Should  Throw
      }
     # test3 : incorrect  list provided.
      It 'throw an exception if non existing List provided.' {
         {Remove-ShPoListItem -fSiteURL $fSiteURLGood -fListName 'Strange_ShouldNotBeHere' -fListItemID '1' } |  Should  Throw
      }
    }
   Context 'Running happy paths with no credentials specified.' {
    #test 1 update items Title.
     it "Delete item with Id $($itemsIds[0]) " {
        {Remove-ShPoListItem -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListItemID "$($itemsIds[0])"} | Should not Throw
     }
     it "Delete item with Id $($itemsIds[1]) if nothing is returned. " {
        Remove-ShPoListItem -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListItemID "$($itemsIds[1])"| Should be $null
     }
     it "Delete items from 3 to 10 in sequence " {
       { 2..9 | foreach-object { Remove-ShPoListItem -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListItemID "$($itemsIds[$_])"}}| Should not Throw
     }
  }
}


#list field -----------------------------------------------------
# describes the function New-ShPoFieldObject
Describe 'New-ShPoFieldObject' {

   Context 'Running obvious unhappy paths'    {
     # test 1: throw an exception if no parameters are set:
      It 'throw an exception if no parameters are set' {
        {New-ShPoFieldObject } | Should  Throw
      }
     # test 2: only field type is provided.
      It 'throw an exception if only field type is provided' {
         {New-ShPoFieldObject -FieldType Field   } |  Should  Throw
      }
      # test 3: Empty string for field Title provided
      It 'throw an exception if Empty string for field Title provided' {
         {New-ShPoFieldObject -FieldType Field -Title ''   } |  Should  Throw
         {New-ShPoFieldObject -FieldType Field -Title $null  } |  Should  Throw
      }
   }
   Context 'Running happy paths' {
    # test 1: throw an exception if no parameters are set:
      It 'creates hashtable for FieldType: Field' {
        $r = New-ShPoFieldObject -FieldType Field -Title 'F1' | Should BeOfType System.Collections.Hashtable
      }
   }

}
# describes the function Add-ShPoListField
Describe 'Add-ShPoListField' {
 # create some items in the list
  BeforeAll {
    try {remove-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{}
    try {Add-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{}
    1..10 | ForEach-Object {@{ 'Title'= "Waldo_$($_)"  }} |
    ForEach-Object { Add-ShPoListItem -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListFields $_ }


     try {remove-ShPoList -fSiteURL $fSiteURLGood -fListName "$fListLookup"} catch{}
     try {$LookUpListId = (Add-ShPoList -fSiteURL $fSiteURLGood -fListName "$fListLookup").Id } catch{}
     1..5 | ForEach-Object {@{ 'Title'= "TestLookup Option_$($_)"  }} |
     ForEach-Object { Add-ShPoListItem -fSiteURL $fSiteURLGood -fListName "$fListLookup" -fListFields $_ }
  }

  # scenario 1: Unhappy path
  Context 'Running obvious unhappy paths'  {
    # test 1: throw an exception if no parameters are set:
    It 'throw an exception if no parameters are set' {
      {Add-ShPoListField } | Should  Throw
    }
    # test 2: incorrect  fSiteURL
    It 'throw an exception if incorrect  fSiteURL' {
       {Add-ShPoListField -fSiteURL $fSiteURLBad -fListName 'Strange_ShouldNotBeHere'  } |  Should  Throw
    }
    # test3 : incorrect  list provided.
    It 'throw an exception if non existing List provided.' {
       {Add-ShPoListField -fSiteURL $fSiteURLGood -fListName 'Strange_ShouldNotBeHere' `
                          -fListFieldDefinition ( New-ShPoFieldObject -FieldType Field -Title 'Field') } |  Should  Throw
    }


  }
  # scenario 2: happy song..
  Context 'Running happy paths with no credentials specified.  ' {
    It 'create simple yes/No field named Field1' {
      $field=New-ShPoFieldObject -FieldType Field -Title 'Field1'
      $createdField = Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListFieldDefinition $field
      $createdField.Title | should be 'Field1'
    }
    It 'create FieldChoice field named Choice1' {
      $field=New-ShPoFieldObject -FieldType FieldChoice -Title 'Choice1' -FillInChoice $true -Choices "Be","Not to Be", "Whatever"  -DefaultValue 'Be' -Description "main question"
      $createdField = Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListFieldDefinition $field
      $createdField.Title | should be 'Choice1'
      $createdField.TypeAsString | should be 'Choice'
      $createdField.DefaultValue  |should be 'Be'
      $createdField.Description | should be "main question"
      $createdField.FillInChoice | should be True
    }
    It 'create FieldDateTime named Date1.  fListFieldDefinition provided by pipeline.' {
      $createdField = New-ShPoFieldObject -FieldType FieldDateTime -Title 'Date1' -Description 'select date' -DisplayFormat 0 -FriendlyDisplayFormat 1 |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew
      $createdField.Title | should be 'Date1'
      $createdField.TypeAsString | should be 'DateTime'
      $createdField.Description | should be "select date"
    }
    It 'create FieldLookup ' {
      $createdField = New-ShPoFieldObject -FieldType FieldLookup -Title 'LookUp1' -Description 'choose option' -LookupField 'Title' -LookupList $fListLookup |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew
      $createdField.Title | should be 'LookUp1'
      $createdField.Description | should be 'choose option'
      $createdField.AllowMultipleValues | should be 'False'
    }
    It 'create FieldLookup with multichoice ' {
      $createdField = New-ShPoFieldObject -FieldType FieldLookup -Title 'LookUp2' -Description 'choose option' -LookupField 'Title' -LookupList $fListLookup -AllowMultipleValues $true |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew
      $createdField.Title | should be 'LookUp2'
      $createdField.Description | should be 'choose option'
      $createdField.AllowMultipleValues | should be 'True'
    }
    It 'Create FieldMultiLineText' {
      $createdField = New-ShPoFieldObject -FieldType FieldMultiLineText -Title 'MultiLine1' -DefaultValue 'Default value1' -Description 'wite the poem here' -RichText $false -NumberOfLines 6 |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew
      $createdField.Title | Should be 'MultiLine1'
      $createdField.NumberOfLines | should be 6
      $createdField.Description | Should be 'wite the poem here'
      $createdField.RichText | should be 'False'

    }
    It 'Create FieldNumber' {
      $createdField  = New-ShPoFieldObject -FieldType FieldNumber -Title 'Number1' -MinimumValue -100 -MaximumValue 100 -Decimals 3 -Percentage $true -DefaultValue 10 -Description 'this is number' |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew
      $createdField.Title | should be 'Number1'
      $createdField.MaximumValue | should be 100
      $createdField.MinimumValue | should be -100
      $createdField.TypeAsString | should be 'Number'
      $createdField.DefaultValue | Should be 10
      $createdField.Description | Should be 'this is number'
      $SchemaXml =[xml]$createdField.SchemaXml
      $SchemaXml.Field.Percentage | should be 'TRUE'
      $SchemaXml.Field.Decimals | should be 3
    }
    It 'Create FieldText' {
      $createdField = New-ShPoFieldObject -FieldType FieldText -Title 'Text1' -DefaultValue 'some text' -Description 'text line to fill' -MaxLength 20 -Required $true |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew
      $createdField.Title | Should be 'Text1'
      $createdField.MaxLength | Should be 20
      $createdField.DefaultValue | Should be  'some text'
      $createdField.Required | Should be 'True'
      $createdField.TypeAsString | Should be 'Text'
    }
    It 'Create FieldMultiChoice' {
       $createdField = New-ShPoFieldObject -FieldType FieldMultiChoice -Title 'MultiChoice1' -Choices 'M1','M2','M3','M4' |
       Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew
       $createdField.TypeAsString  | should be 'MultiChoice'
       $createdField.Title | Should be 'MultiChoice1'
       $createdField.Choices.results -contains 'M2' | should Be $true
    }
  }

  Context 'Running happy path pype properties by name.' {
    It 'create text field ' {
      $TextFieldDescription = New-Object PsObject -Property @{
        Title = 'Text3'
        DefaultValue = 'value1'
        MaxLength = 10
        Required = $false
      }
      $createdField = $TextFieldDescription | New-ShPoFieldObject -FieldType FieldText |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew
      $createdField.Title | Should be $TextFieldDescription.Title
      $createdField.MaxLength | Should be $TextFieldDescription.MaxLength
      $createdField.DefaultValue | Should be  $TextFieldDescription.DefaultValue
      $createdField.Required | Should be "$($TextFieldDescription.Required)"
      $createdField.TypeAsString | Should be 'Text'

    }
  }

}
# describes the function Remove-ShPoListField
Describe 'Remove-ShPoListField' {
  BeforeAll {
    try {remove-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{}
    try {Add-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{}
    1..10 | ForEach-Object {@{ 'Title'= "Waldo_$($_)"  }} |
    ForEach-Object { Add-ShPoListItem -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListFields $_ }

    try{
	  $Doing = "Adding field Text1"
      New-ShPoFieldObject -FieldType FieldText -Title 'Text1' -DefaultValue 'some text' -Description 'text line to fill' -MaxLength 20 -Required $true |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew
	  $Doing = "Adding field Number1"
      New-ShPoFieldObject -FieldType FieldText -Title 'Number1' |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew
	  $Doing = "Adding field Number2"
      New-ShPoFieldObject -FieldType FieldText -Title 'Number2' |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew
	  $Doing = "Adding field Number3"
      New-ShPoFieldObject -FieldType FieldText -Title 'Number3' |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew
    }
    catch
    {
		Write-Host "Test preparations failed during $doing, expect errors to happen; reason: $($_.Exception.Message)" -ForegroundColor Red
	}
  }
    # scenario 1: Unhappy path
  Context 'Running obvious unhappy paths'  {
    # test 1: throw an exception if no parameters are set:
    It 'throw an exception if no parameters are set' {
      {Remove-ShPoListField } | Should  Throw
    }
    # test 2: incorrect  fSiteURL
    It 'throw an exception if incorrect  fSiteURL' {
       {Remove-ShPoListField -fSiteURL $fSiteURLBad -fListName 'Strange_ShouldNotBeHere'  } |  Should  Throw
    }
    # test3 : incorrect  list provided.
    It 'throw an exception if non existing List provided.' {
       {Remove-ShPoListField -fSiteURL $fSiteURLGood -fListName 'Strange_ShouldNotBeHere' `
                          -fListFieldTitle 'Text1' } |  Should  Throw
    }
    # test4 : incorrect  list  field provided.
    It 'throw an exception if non existing List field provided.' {
      {Remove-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew `
                          -fListFieldTitle 'NoSuchField' } |  Should  Throw
    }
    It 'throw an exception if no List field provided.' {
      {Remove-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew `
                          -fListFieldTitle 'NoSuchField' } |  Should  Throw
    }
  }
  Context 'Running happy path test' {
    It 'Delete field named Text1 of type Text.' {
      $result = Remove-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListFieldTitle 'Text1'
      $result | should be $null
    }
    It 'Delete field named Numer1 of type Number, to check if no exception received.' {
      {Remove-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListFieldTitle 'Number1' } | Should not throw

    }
    It 'Delete multiple fields in one call, to check if no exception received.' {
      {Remove-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListFieldTitle 'Number2','Number3' } | Should not throw

    }

  }
}
# describes the function Update-ShPoListField
Describe 'Update-ShPoListField' {
  BeforeAll {
    try {remove-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{}
    try {Add-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{}
    1..10 | ForEach-Object {@{ 'Title'= "Waldo_$($_)"  }} |
    ForEach-Object { Add-ShPoListItem -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListFields $_ }
    try {remove-ShPoList -fSiteURL $fSiteURLGood -fListName "$fListLookup"} catch{}
    try {$LookUpListId = (Add-ShPoList -fSiteURL $fSiteURLGood -fListName "$fListLookup").Id } catch{}
    try{ 1..5 | ForEach-Object {@{ 'Title'= "TestLookup Option_$($_)"  }} |
    ForEach-Object { Add-ShPoListItem -fSiteURL $fSiteURLGood -fListName "$fListLookup" -fListFields $_ }} catch {}

    #create some fields for testing...
    try {
      $Doing = "Adding field Field1"
	  $FieldId = (New-ShPoFieldObject -FieldType Field -Title 'Field1' | Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew).Id
      $FieldChoiceId = (New-ShPoFieldObject -FieldType FieldChoice -Title 'Choice1' -FillInChoice $true -Choices "Be","Not to Be", "Whatever"  -DefaultValue 'Be' -Description "main question" |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew).Id
      $Doing = "Adding field Date1"
      $FieldDateTimeId = (New-ShPoFieldObject -FieldType FieldDateTime -Title 'Date1' -Description 'select date' -DisplayFormat 0 -FriendlyDisplayFormat 1 |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew).Id
      $Doing = "Adding field LookUp1"
      $FieldLookupId= (New-ShPoFieldObject -FieldType FieldLookup -Title 'LookUp1' -Description 'choose option' -LookupField 'Title' -LookupList $fListLookup |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew).Id
      $Doing = "Adding field MuiltiLine1"
      $FieldMultiLineText = (New-ShPoFieldObject -FieldType FieldMultiLineText -Title 'MultiLine1' -DefaultValue 'Default value1' -Description 'wite the poem here' -RichText $false -NumberOfLines 6 |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew).Id
      $Doing = "Adding field Text1"
      $FieldText = (New-ShPoFieldObject -FieldType FieldText -Title 'Text1' -DefaultValue 'some text' -Description 'text line to fill' -MaxLength 20 -Required $true |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew).Id
      $Doing = "Adding field Number1"
      $FieldNumberId = (New-ShPoFieldObject -FieldType FieldNumber -Title 'Number1' -MinimumValue -100 -MaximumValue 100 -Decimals 3 -Percentage $true -DefaultValue 10 -Description 'this is number' |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew).Id
    }
    catch     {
		Write-Host "Test preparations failed during $doing, expect errors to happen; reason: $($_.Exception.Message)" -ForegroundColor Red
	}
  }
  # scenario 1: Unhappy path
  Context 'Running obvious unhappy paths'  {
    # test 1: throw an exception if no parameters are set:
    It 'throw an exception if no parameters are set' {
      {Update-ShPoListField} | Should  Throw
    }
    # test 2: incorrect  fSiteURL
    It 'throw an exception if incorrect  fSiteURL' {
       {Update-ShPoListField -fSiteURL $fSiteURLBad -fListName 'Strange_ShouldNotBeHere'  } |  Should  Throw
    }
    # test3 : incorrect  list provided.
    It 'throw an exception if non existing List provided.' {
       {Update-ShPoListField -fSiteURL $fSiteURLGood -fListName 'Strange_ShouldNotBeHere' `
                          -FieldType Field } |  Should  Throw
    }
    It 'throw an exception if no properties to update provided' {
       {Update-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew `
                          -FieldType Field  -Id $FieldId } |  Should  Throw
    }


  }
  # scenario 2: Happy path
  Context 'Running happy paths' {
    It 'Update Field description' {
      $updatedField = Update-ShPoListField -FieldType Field -Id $FieldId -Description 'new description' -fListName $fListNameNew -fSiteURL $fSiteURLGood
      $updatedField.Description | Should be 'new description'
    }
    It 'Update FieldChoice with new choices' {
      $updatedField = Update-ShPoListField -fListName $fListNameNew -fSiteURL $fSiteURLGood -FieldType FieldChoice -Id $FieldChoiceId -Choices 'one','two','other'
      $updatedField.Choices.results -contains 'One' | should be true
    }
    It 'Update FieldDateTime display fromat' {
      $updatedField = Update-ShPoListField -fListName $fListNameNew -fSiteURL $fSiteURLGood -FieldType FieldDateTime -Id $FieldDateTimeId -DisplayFormat 1
      $updatedField.DisplayFormat | should be 1
    }
    It 'Update Fieldlookup field to allow multichoice.' {
      $updatedField = Update-ShPoListField -fListName $fListNameNew -fSiteURL $fSiteURLGood -FieldType FieldLookup -Id $FieldLookupId -AllowMultipleValues $true
      $updatedField.AllowMultipleValues | should be "True"
    }
    It 'Update FieldMultiLineText line number' {
      $updatedField = Update-ShPoListField -fListName $fListNameNew -fSiteURL $fSiteURLGood -FieldType FieldMultiLineText -Id $FieldMultiLineText -NumberOfLines 2
      $updatedField.NumberOfLines | should be 2
    }
    It 'Update FieldText maxlength' {
      $updatedField = Update-ShPoListField -fListName $fListNameNew -fSiteURL $fSiteURLGood -FieldType FieldText -Id $FieldText -MaxLength 100
      $updatedField.MaxLength | should be 100
    }
    It 'Update FieldNumber to be not Percentage, and max & min values' {
      $updatedField = Update-ShPoListField -fListName $fListNameNew -fSiteURL $fSiteURLGood -FieldType FieldNumber -Id  $FieldNumberId -MaximumValue 300 -Percentage $false -MinimumValue -200
      $updatedField.MaximumValue | Should be 300
      $updatedField.MinimumValue | Should be -200
      $schemaXml = [xml]$updatedField.SchemaXml
      $schemaXml.Field.Percentage | Should be 'False'
    }

  }

}
# describes the function Get-ShPoField
Describe 'Get-ShPoField' {
  BeforeAll {
    try {remove-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{}
    try {Add-ShPoList -fSiteURL $fSiteURLGood -fListName $fListNameNew } catch{}
    1..10 | ForEach-Object {@{ 'Title'= "Waldo_$($_)"  }} |
    ForEach-Object { Add-ShPoListItem -fSiteURL $fSiteURLGood -fListName $fListNameNew -fListFields $_ }
    try {remove-ShPoList -fSiteURL $fSiteURLGood -fListName "$fListLookup"} catch{}
    try {$LookUpListId = (Add-ShPoList -fSiteURL $fSiteURLGood -fListName "$fListLookup").Id } catch{}
    try{ 1..5 | ForEach-Object {@{ 'Title'= "TestLookup Option_$($_)"  }} |
    ForEach-Object { Add-ShPoListItem -fSiteURL $fSiteURLGood -fListName "$fListLookup" -fListFields $_ }} catch {}

    #create some fields for testing...
    try {
      $Doing = "Adding field Field1"
	  $FieldId = (New-ShPoFieldObject -FieldType Field -Title 'Field1' | Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew).Id
      $Doing = "Adding field 'Choice1"
      $FieldChoiceId = (New-ShPoFieldObject -FieldType FieldChoice -Title 'Choice1' -FillInChoice $true -Choices "Be","Not to Be", "Whatever"  -DefaultValue 'Be' -Description "main question" |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew).Id
      $Doing = "Adding field Date1"
      $FieldDateTimeId = (New-ShPoFieldObject -FieldType FieldDateTime -Title 'Date1' -Description 'select date' -DisplayFormat 0 -FriendlyDisplayFormat 1 |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew).Id
      $Doing = "Adding field LookUp1"
      $FieldLookupId= (New-ShPoFieldObject -FieldType FieldLookup -Title 'LookUp1' -Description 'choose option' -LookupField 'Title' -LookupList $fListLookup |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew).Id
      $Doing = "Adding field MultiLine1"
      $FieldMultiLineText = (New-ShPoFieldObject -FieldType FieldMultiLineText -Title 'MultiLine1' -DefaultValue 'Default value1' -Description 'wite the poem here' -RichText $false -NumberOfLines 6 |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew).Id
      $Doing = "Adding field Text1"
      $FieldTextId = (New-ShPoFieldObject -FieldType FieldText -Title 'Text1' -DefaultValue 'some text' -Description 'text line to fill' -MaxLength 20 -Required $true |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew).Id
      $Doing = "Adding field Number1"
      $FieldNumberId = (New-ShPoFieldObject -FieldType FieldNumber -Title 'Number1' -MinimumValue -100 -MaximumValue 100 -Decimals 3 -Percentage $true -DefaultValue 10 -Description 'this is number' |
      Add-ShPoListField -fSiteURL $fSiteURLGood -fListName $fListNameNew).Id
    }
    catch {
		Write-Host "Test preparations failed during $doing, expect errors to happen; reason: $($_.Exception.Message)" -ForegroundColor Red
	}
  }
    # scenario 1: Unhappy path
  Context 'Running obvious unhappy paths'  {
    # test 1: throw an exception if no parameters are set:
    It 'throw an exception if no parameters are set' {
      {Get-ShPoField} | Should  Throw
    }
    # test 2: incorrect  fSiteURL
    It 'throw an exception if incorrect  fSiteURL' {
       {Get-ShPoField -fSiteURL $fSiteURLBad -fListName $fListNameNew } |  Should  Throw
    }
    # test3 : incorrect  list provided.
    It 'throw an exception if non existing List provided.' {
       {Get-ShPoField  -fSiteURL $fSiteURLGood -fListName 'Strange_ShouldNotBeHere' } |  Should  Throw
    }
    It 'throw an exception if incorect field name provided.' {
       {Get-ShPoField  -fSiteURL $fSiteURLGood -fListName $fListNameNew `
                          -fListFieldTitle "NoSuchField" } |  Should  Throw
    }
  }
  # scenario 2: Happy path
  Context 'Running happy paths' {
    It 'Get all fields from list.' {
      (Get-ShPoField -fSiteURL $fSiteURLGood -fListName $fListNameNew).count | should BeGreaterThan 50
    }
    It 'Get all fields from list with all fields properties..' {
      $result =Get-ShPoField -fSiteURL $fSiteURLGood -fListName $fListNameNew -fFull
      ($result[0] | Get-Member ).count | should BeGreaterThan 20
    }
    It 'Get field by ID' {
      (Get-ShPoField -fSiteURL $fSiteURLGood -fListName $fListNameNew -fFull -fListFieldId $FieldTextId).Title | should be 'Text1'
    }
    It 'Get field by Title' {
      (Get-ShPoField -fSiteURL $fSiteURLGood -fListName $fListNameNew -fFull -fListFieldTitle 'Text1').Id | should be $FieldTextId
    }
  }
}
