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
#    2018-07-06 JFL Added support for wildcard in the arguments.              #
#                   Added support for files renamed without the CPnnnnnn part.#
#                   Display a warning when encountering an HP SP*.exe file.   #
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
  
  Note: Do not confuse HPE "CPnnnnnn.EXE" smart updates, and HP "SPnnnnnn.exe"
  support programs. This script handles HPE's CP*.exe, but not HP's SP*.exe,
  as the latter have no standard XML descriptor file.

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
  C:\PS> Get-SmartUpdateInfo cp*.exe | ft -a
  Get default information about all Smart Updates in the current directory.

  .EXAMPLE
  C:\PS> dir | Get-SmartUpdateInfo | ft -a
  Get default information about all Smart Updates in the current directory.
#>

[CmdletBinding(DefaultParameterSetName='GetInfo')]
Param (
  [Parameter(ParameterSetName='GetFileInfo', Position=0, ValueFromPipeline=$true, Mandatory=$true)]
  [System.IO.FileSystemInfo[]]$File,	# Smart Update FileSystemInfo

  [Parameter(ParameterSetName='GetNameInfo', Position=0, ValueFromPipeline=$true, Mandatory=$true)]
  [String[]]$Name,			# Smart Update name

  [Parameter(ParameterSetName='GetNameInfo')]
  [Parameter(ParameterSetName='GetFileInfo')]
  [String]$Lang = "en",			# The default language to use for localized fields

  [Parameter(ParameterSetName='GetNameInfo')]
  [Parameter(ParameterSetName='GetFileInfo')]
  [Switch]$V,				# If true, display verbose information

  [Parameter(ParameterSetName='GetNameInfo')]
  [Parameter(ParameterSetName='GetFileInfo')]
  [Switch]$Quiet,			# If true, do NOT display debug or verbose information

  [Parameter(ParameterSetName='Version', Mandatory=$true)]
  [Switch]$Version			# If true, display the script version
)

Begin {
  
# If the -Version switch is specified, display the script version and exit.
$scriptVersion = "2018-07-06"
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
  # Note: PowerShell is inconsistent in the way it converts System.IO.FileSystemInfo to string:
  # "$((dir \)[-1])" = _Backup_Files.txt
  # "$((dir \*.txt)[-1])" = C:\_Backup_Files.txt
  # This makes it unreliable to use just a String argument, as the path is sometimes lost.
  # Instead, accept either string or System.IO.FileSystemInfo objects
  if ($File) { # We got a System.IO.FileSystemInfo object
    Write-Debug "Process FileSystemInfo '$($File.FullName)'"
    $Files = $File
  } else { # We got a string object
    Write-Debug "Process String '$Name'"
    $Files = dir $Name # Allow processing string arguments that do contain wildcards
  }
  $Files | % {
    Write-Debug "Inner loop: File='$_' ; PSIsContainer=$($_.PSIsContainer)"
    if ($_.PSIsContainer) { return } # Skip subdirectories
    $File = $_
    $absName = $File.FullName
    $Base = $File.BaseName
    # Allow cases when a Smart Update has been renamed with a description along with the CPnnnnnn reference
    if ($base -match "cp\d\d\d\d+") {
      $base = $matches[0]
    } else {
      $base = "cp*"
    }
    $xmlName = "${Base}.xml"
    Write-Verbose "Extracting $xmlName from '$absName'"
    try {
      # Extract the XML description file from the Smart Update
      $zip = [System.IO.Compression.ZipFile]::OpenRead($absName)
      if (!$zip) {
      	throw "Can't open Zip file '$absName'"
      }
      $xmlEntry = $zip.Entries | where {$_.Name -like $xmlName}
      if (!$xmlEntry) {
      	throw "Can't find $xmlName in '$absName'"
      }
      $Base = $xmlEntry.Name -replace ".xml$",""
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
      	FileName = $absName
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
      $msg = $_.Exception.Message
      # Fail silently in case of error, except in debug mode
      # This allows passing in all files in the directory, and get results for the valid Smart Updates only.
      if ($Debug) {
	Write-Error "Error: $msg"
      }
      # Special case of a common error that we want to point out anyway
      if ($File.Name -match "sp\d\d\d\d.*\.exe") {
	Write-Warning "'$absName' looks like an HP SP*.exe Support Program, not like an HPE CP*.exe Smart Update."
      }
      # In verbose mode, make it clear that we saw the file, and why we skipped it 
      Write-Verbose "Skipping '$absName', which is not a Smart Update"
    }
  }
}

End {
}

