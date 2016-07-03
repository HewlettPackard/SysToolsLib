###############################################################################
#                                                                             #
#   Filename        Get-SmartUpdateInfo.ps1                                   #
#                                                                             #
#   Description     Display information about HP Smart Update CPnnnnnn.EXE    #
#                                                                             #
#   Notes           TO DO: Rework the XML extraction code, so that it finds   #
#                   it even if the Smart Update name does not contain the     #
#                   CPnnnnnn reference anymore.                               #
#                                                                             #
#   History                                                                   #
#    2014-10-21 JFL Created this script.                                      #
#    2014-12-01 JFL Renamed this script, to be more coherent with HPSUM name. #
#    2015-10-06 JFL Fixed debug output, and added option -Quiet.              #
#    2016-01-15 JFL Bug fix: Work with extended names with a description.     #
#                                                                             #
#         © Copyright 2016 Hewlett Packard Enterprise Development LP          #
# Licensed under the Apache 2.0 license - www.apache.org/licenses/LICENSE-2.0 #
###############################################################################

<#
  .SYNOPSIS
  Display information about HP Smart Update "CPnnnnnn.EXE"

  .DESCRIPTION
  Extracts their XML description file, and displays a selection of data fields
  from that XML file:
  name, content, version, release date, description, category, etc.

  Requires PowerShell 3 with .NET 4.5 installed.

  .PARAMETER Name
  File name(s) of the Smart Update(s).
  Either specified as an argument, or received from the input pipeline.
  
  If a name is invalid, or refers to a file that is not a Smart Update,
  then the script does nothing. This allows passing in the list of all files
  in a directory, and get results for all those that are valid components.

  .PARAMETER Lang
  The preferred language code to use for localized fields. Default: en
  One of: en, ja, cn, tw, ko, ...
  If the localized field is absent for the requested language, en will be used.

  .PARAMETER Quiet
  Ignore Debug or Verbose preferences, and do not display any debug or verbose
  information.

  .EXAMPLE
  C:\PS> Get-SmartUpdateInfo cp017534.exe | fl *
  Get all available information about a specific Smart Update.

  .EXAMPLE
  C:\PS> dir | Get-SmartUpdateInfo | ft -a
  Get default information about all Smart Updates in the current directory.
#>

[CmdletBinding(DefaultParameterSetName='GetInfo')]
Param (
  [Parameter(ParameterSetName='GetInfo', Position=0, ValueFromPipeline=$true, Mandatory=$true)]
  [String[]]$Name,			# Smart Update name

  [Parameter(ParameterSetName='GetInfo')]
  [String]$Lang = "en",			# The default language to use for localized fields

  [Parameter(ParameterSetName='GetInfo')]
  [Switch]$V,				# If true, display verbose information

  [Parameter(ParameterSetName='GetInfo')]
  [Switch]$Quiet,			# If true, do NOT display debug or verbose information

  [Parameter(ParameterSetName='Version', Mandatory=$true)]
  [Switch]$Version			# If true, display the script version
)

Begin {
  
# If the -Version switch is specified, display the script version and exit.
$scriptVersion = "2016-01-15"
if ($Version) {
  echo $scriptVersion
  exit
}

if ($Quiet) {
  $DebugPreference = "SilentlyContinue"
  $VerbosePreference = "SilentlyContinue"
}

###############################################################################
#                                                                             #
#                              Debugging library                              #
#                                                                             #
###############################################################################

$argv0 = $MyInvocation.MyCommand.Definition
$script = (dir $argv0).basename

# Redefine the colors for a few message types
$colors = (Get-Host).PrivateData
if ($colors) { # Exists for ConsoleHost, but not for ServerRemoteHost
  $colors.VerboseForegroundColor = "white" # Less intrusive than the default yellow
  $colors.DebugForegroundColor = "cyan"	 # Distinguish debug messages from yellow warning messages
}

if ($D -or ($DebugPreference -ne "SilentlyContinue")) {
  $Debug = $true
  $DebugPreference = "Continue"	    # Make sure Write-Debug works
  $V = $true
  Write-Debug "# Running in debug mode."
} else {
  $Debug = $false
  $DebugPreference = "SilentlyContinue"	    # Write-Debug does nothing
}

if ($V -or ($VerbosePreference -ne "SilentlyContinue")) {
  $Verbose = $true
  $VerbosePreference = "Continue"   # Make sure Write-Verbose works
  Write-Debug "# Running in verbose mode."
} else {
  $Verbose = $false
  $VerbosePreference = "SilentlyContinue"   # Write-Verbose does nothing
}

# No need for the rest of my debugging library for now.

#-----------------------------------------------------------------------------#

# Convert a relative or absolute path to a canonic absolute path.
Function Get-AbsolutePath ($Path) {
  # System.IO.Path.Combine has two properties making it necesarry here:
  #   1) correctly deals with situations where $Path (the second term) is an absolute path
  #   2) correctly deals with situations where $Path (the second term) is relative
  # (join-path) commandlet does not have this first property
  $Path = [System.IO.Path]::Combine( ((pwd).Path), ($Path) );

  # this piece strips out any relative path modifiers like '..' and '.'
  $Path = [System.IO.Path]::GetFullPath($Path);

  return $Path;
}

# Get a translated element
Function Get-TranslatedString ($xmlText, $xpath, $Lang) {
  $node = (Select-Xml "$xpath[@lang='$Lang']" -Content $xmlText).Node
  if (!$node) {
    $node = (Select-Xml "$xpath[@lang='en']" -Content $xmlText).Node.'#Text'
  }
  if (!$node) {
    return $null
  }
  $string = $node.'#text'
  if (!$string) {
    $string = $node.'#cdata-section'
  }
  return $string
}

#-----------------------------------------------------------------------------#
#                                                                             #
#   Function        Main                                                      #
#                                                                             #
#   Description     Execute the specified actions                             #
#                                                                             #
#   Arguments       See the Param() block at the top of this script           #
#                                                                             #
#   Notes 	                                                              #
#                                                                             #
#   History                                                                   #
#    2014-10-21 JFL Created this script.                                      #
#                                                                             #
#-----------------------------------------------------------------------------#

# Load objects necessary for accessing zip files
Add-Type -Assembly System.IO.Compression.FileSystem

# Define a .PSStandardMembers.DefaultDisplayPropertySet to control the fields displayed by default, and their order
$DefaultFieldsToDisplay = 'Name','Content','Version','Date'
$defaultDisplayPropertySet = New-Object System.Management.Automation.PSPropertySet(
  'DefaultDisplayPropertySet',[string[]]$DefaultFieldsToDisplay
)
$PSStandardMembers = [System.Management.Automation.PSMemberInfo[]]@($defaultDisplayPropertySet)

} ; # End of the Begin block

Process {
  $Name | % {
    $absName = Get-AbsolutePath $_
    $Leaf = Split-Path $absName -Leaf
    $Base = $Leaf -replace ".exe$",""
    # Allow cases when a Smart Update has been renamed with a description along with the CPnnnnnn reference
    if ($base -match "cp\d+") {
      $base = $matches[0]
    }
    $xmlName = "${Base}.xml"
    Write-Verbose "Extracting $xmlName from '$absName'"
    try {
      # Extract the XML description file from the Smart Update
      $zip = [System.IO.Compression.ZipFile]::OpenRead($absName)
      if (!$zip) {
      	throw "Can't open Zip file '$absName'"
      }
      $xmlEntry = $zip.Entries | where {$_.Name -eq $xmlName}
      if (!$xmlEntry) {
      	throw "Can't find $xmlName in '$absName'"
      }
      $hXmlEntry = $xmlEntry.open()
      $size = $xmlEntry.Length
      $bytes = New-Object Byte[] $size
      $bytesRead = $hXmlEntry.Read($bytes,0,$size)
      # $xmlText = [System.Text.Encoding]::ASCII.GetString($bytes)
      $xmlText = [System.Text.Encoding]::UTF8.GetString($bytes)

      # Parse the XML, and get various information fields
      $cpVersion = (Select-Xml "/cpq_package/version" -Content $xmlText).Node.value
      $cpName = Get-TranslatedString $xmlText "//name_xlate" $Lang
      $releaseNode = (Select-Xml "//release_date" -Content $xmlText).Node
      $cpDate = Get-Date -Year $releaseNode.year -Month $releaseNode.month -Day $releaseNode.day `
		         -Hour $releaseNode.hour -Minute $releaseNode.minute -Second $releaseNode.second
      $cpMaker = Get-TranslatedString $xmlText "//manufacturer_name_xlate" $Lang
      $cpLanguages = (Select-Xml "/cpq_package/languages" -Content $xmlText).Node.langlist
      $cpCategory = Get-TranslatedString $xmlText "//category_xlate" $Lang
      $cpDescription = Get-TranslatedString $xmlText "//description_xlate" $Lang

      # Create an object with all the information we have
      $object = New-Object PSObject -Property @{
	Name = $Base
	Content = $cpName
	Version = $cpVersion
	Date = "{0:yyyy}-{0:MM}-{0:dd}" -f $cpDate
	Manufacturer = $cpMaker
	Languages = $cpLanguages
	Category = $cpCategory
	Description = $cpDescription
      }
      # Add a .PSStandardMembers.DefaultDisplayPropertySet to control the fields displayed by default, and their order
      $object | Add-Member MemberSet PSStandardMembers $PSStandardMembers

      # Output the result object
      $object
    } catch {
      # Fail silently in case of error, except in debug mode
      if ($Debug) {
	$msg = $_.Exception.Message
	Write-Error "Error: $msg"
      }
      # This allows passing in all files in the directory, and get results for the valid Smart Updates only.
      Write-Verbose "Skipping '$absName', which does not refer to a Smart Update"
    }
  }
}

End {
}

