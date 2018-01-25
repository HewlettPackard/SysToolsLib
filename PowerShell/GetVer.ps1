###############################################################################
#                                                                             #
#   File name       GetVer.ps1                                                #
#                                                                             #
#   Description     Get HP Storage software and firmware versions             #
#                                                                             #
#   Notes                                                                     #
#                                                                             #
#   History                                                                   #
#    2010-07-27 JFL Created this script.                                      #
#    2010-08-26 JFL Fixed a typo which prevented any SEP detection.           #
#                   Added help messages.                                      #
#                   Added an option to query the versions of a remote machine.#
#                   This requires having enabled remote management on that    #
#                   remote machine, by running Enable-PsRemoting there once.  #
#    2010-09-01 JFL Added the system SKU version to the computer section.     #
#    2010-09-02 JFL Added the EM FW date and SVN version to the enclosure sec.#
#                   Fixed a bug which prevented redirection of the stdout.    #
#    2010-10-18 JFL Exclude Exchange Language Packs from the output.          #
#    2010-10-19 JFL Added EM version detection using CMP's Java object.       #
#                   Added a -Version option.                                  #
#                   Display all dates using the ISO 8601 format.              #
#    2010-10-22 JFL Added 32-bits software versions.                          #
#                   Restructured the directory/value output routines.         #
#    2011-03-31 JFL Adapt the EM FW version parsing to the new format.        #
#                   Bugfix: Return to the initial dir. in case of failure.    #
#                   Added Windows version.                                    #
#    2011-04-07 JFL Use product names, not project codenames, in the output.  #
#                   Consistently use model for every item. (no more type)     #
#                   Added model and fw version for the P410i controller.      #
#                   Added model for the internal and mezzanine LANs.          #
#                   Added model for the enclosure (E5300/5500/5700).          #
#                   Bugfix: The computer model sometimes was HP HP something. #
#    2011-04-08 JFL Prevent WMI errors when run on a non-E5000 system.        #
#                   Added the enclosure model for other enclosure types.      #
#    2011-04-14 JFL Added a workaround for CMP regression getting EM FW Ver.  #
#    2011-04-18 JFL Report the actual EM model string. Moved the E5000 model  #
#                   back into the computer section, as a "system" item.       #
#    2011-04-22 JFL Fixed output in debug mode. Use standard debugging cmds.  #
#                   Minor bugfix: Do not display an empty 1210m fw version.   #
#    2011-06-02 JFL Fixed quotes, which caused errors in Korean Windows.      #
#    2011-07-12 JFL Display the 1210m controller CPLD version.                #
#                   Added arguments to use other credentials for remote exec. #
#                   Fixed a bug preventing remote execution in some cases.    #
#    2011-08-16 JFL Added fw version for network controllers.                 #
#                   Restructured the code with 4 main subroutines, that can   #
#                   be invoked independantly by switches -n, -s, -sw, -sys.   #
#    2011-09-12 JFL Added native XML output option -xml.                      #
#                   Modified the seps and sofware sections output to contain  #
#                   only valid XML names.                                     #
#    2011-09-19 JFL Use WMI to get the computer name and domain.              #
#    2011-09-27 JFL Option -Version now displays SVN Revision and Date props. #
#    2011-10-17 JFL Added the blades disks firmware version.                  #
#    2011-10-21 JFL Added the Power Management Controller firmware version.   #
#                   Display the ilo, enclosure, scsi, seps sections only if   #
#                   they're not empty.                                        #
#    2011-11-18 JFL Added the controller cache size.                          #
#    2012-08-16 JFL Generalized for use on non-E5000 HP Storage systems.      #
#    2012-09-17 JFL Improved recognition of generic X1000/X3000/X5000 and     #
#                   E5000 products. Added the X5000 G3 product ID.            #
#                   Changed the versioning scheme to a more classic format:   #
#                   Major.Minor.Update.Build, adapted here as YYYY.MM.DD.SVN. #
#                   Display our own version in the software version list.     #
#    2012-10-22 JFL Recognize new network controllers with no NC prefix.      #
#                   Recognize new integrated SCSI controllers with no i suffix#
#                   Support having multiple integrated SCSI controllers.      #
#                   Recognize the X1000 software image as such.               #
#    2015-10-01 JFL Display the Service Release version.                      #
#    2015-10-08 JFL Fixed the network controller enumeration.                 #
#    2015-10-09 JFL Fixed disk index numbers; Specify the disk port and box.  #
#                   Changed disk size to an integer number of gigabytes.      #
#                                                                             #
#         © Copyright 2018 Hewlett Packard Enterprise Development LP          #
# Licensed under the Apache 2.0 license - www.apache.org/licenses/LICENSE-2.0 #
###############################################################################

<#
  .SYNOPSIS
  Get HP Storage software and firmware versions

  .DESCRIPTION
  Display a structured list of HP software and firmware versions,
  either from the local or a remote machine.
  This list can be easily read by humans, or processed by programs.
  It can also easily be converted to XML using the sml.tcl script.

  Note that for successfully accessing a remote machine, this remote machine
  must have been prepared by running Enable-PsRemoting on it beforehand once.
  Also the selected user must have administrator rights on the remote machine.

  .PARAMETER ComputerName
  The target machine name. Default: . = localhost

  .PARAMETER UserName
  The user name to use to login on the target machine. Default: The current user

  .PARAMETER Password
  The user name to use to login on the target machine. Default: Prompt for it.
  Warning: Writing passwords on a command line is convenient, but dangerous!

  .PARAMETER Network
  If this switch is specified, display only network controllers information.
  Alias: -n

  .PARAMETER Storage
  If this switch is specified, display only storage controllers information.
  Alias: -s

  .PARAMETER Software
  If this switch is specified, display only software information.
  Alias: -sw

  .PARAMETER System
  If this switch is specified, display only BIOS, iLO, and enclosure information.
  Alias: -sys

  .PARAMETER Verbose
  If the -Verbose switch is specified, display extra information.
  Alias: -v

  .PARAMETER Version
  If the -Version switch is specified, display this script version.

  .PARAMETER NoExec
  If the -NoExec switch is specified, display the commands to execute,
  but do not execute them.
  Alias: -X

  .PARAMETER XML
  If the -NoExec switch is specified, output "normal" XML instead of the
  simplified human-friendly version output by default.

  .EXAMPLE
  C:\PS> GetVer.ps1
  Get the local machine version information.

  .EXAMPLE
  C:\PS> GetVer.ps1 idpb1
  Get version information from remote machine idpb1.
#>

[CmdletBinding()]		    # Brings standard params $Verbose, $Debug, ... 
Param (
  $ComputerName = ".",     	    # Target machine name. Default: .=localhost
  $UserName,			    # User name for remote login. Default: self
  $Password,			    # Password for remote login. Default: prompt
  [Switch][alias("n")]$Network,	    # If true, display only network information
  [Switch][alias("s")]$Storage,	    # If true, display only storage information
  [Switch][alias("sw")]$Software,   # If true, display only software information
  [Switch][alias("sys")]$System,    # If true, display only system information
  [Switch]$V,			    # If true, display extra information
  [Switch]$Version,		    # If true, display the script version
  [Switch][alias("X")]$NoExec,	    # If true, display but don't execute
  [Switch]$XML			    # If true, output XML instead of SML
)

$svn='$Revision: 1468 $Date: 2015-10-09$' ; # Updated by SVN at checkin

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
#                                                                             #
#   Function        Quote                                                     #
#                                                                             #
#   Description     Put quotes around a string, if needed for reinterpretation#
#                                                                             #
#   Notes           Quoting constraints:                                      #
#                   - 'strings' contents are left unchanged.                  #
#                   - "strings" contents special characters are interpreted.  #
#                   - We try to minimize the number of ` escape sequences.    #
#                   - We prefer "strings" first (Looking more natural),       #
#                     then 'strings' (Possibly for a second level of quoting).#
#                                                                             #
#   History                                                                   #
#    2010-06-08 JFL Created this routine.                                     #
#    2010-06-17 JFL Added special handling for $null and arrays.              #
#    2010-06-24 JFL Added special handling for hash tables.                   #
#    2010-07-23 JFL Added special handling for booleans.                      #
#    2013-07-19 JFL Added special handling for blocks of code.                #
#    2013-10-07 JFL Added special handling for Parameter lists.               #
#    2013-11-18 JFL Added special handling for enumerations and types.        #
#                   Display the default fields for objects that have an       #
#                   explicit or default format definition.                    #
#                                                                             #
#-----------------------------------------------------------------------------#

$ImplicitTypes = "System.String", "System.Decimal", "System.Single", "System.Double", 
                 "System.Char", "System.Int16", "System.Int32", "System.Int64",
                 "System.Byte", "System.UInt16", "System.UInt32", "System.UInt64"

Function Quote(
  $var, # Don't set $var type at this stage, to catch $null, etc.
  [Switch]$Force # $True=Quote all strings; $false=Only when necessary
) {
  if ($var -eq $null) { # Special case of the $null object
    return '$null'
  }
  if (($var -is [Boolean]) -or ($var -is [System.Management.Automation.SwitchParameter])) { # Special case of booleans
    if ($var) {
      return '$True'
    } else {
      return '$False'
    }
  }
  if ($var -is [Array]) { # This is an array. Return a list of quoted array members.
    return "@($(($var | foreach { Quote $_ -Force }) -join ", "))"
  }
  if ($var -is [Hashtable]) { # This is a hash table. Sort keys which are ordered randomly by hash.
    return "@{$(($var.Keys | sort | foreach { "$_ = $(Quote $var.$_ -Force )" }) -join "; ")}"
  }
  if ($var -is [Enum]) { # This is an enumeration. Force quoting string values to avoid issues with object members (which are often enums).
    return Quote "$var" -Force
  }
  if ($var -is [type]) { # This is a type. Return its name as a cast.
    return "[$($var.Name)]"
  }
  if ($var -is [ScriptBlock]) { # This is a block of code. Return it in curly brackets.
    return "{$var}"
  }
  $type = $var.psTypeNames[0] # Try using this type name, which is sometimes more descriptive than the official one in GetType().FullName
  if ($type -eq $null) { # $type seems to be always defined, but just in case, if it's not, fallback to the documented name.
    $type = $var.GetType().FullName
  }
  if (    $type -eq "System.Management.Automation.PSBoundParametersDictionary" `
      -or $type -like "System.Collections.Generic.Dictionary*") { # This is a dictionary. Keys are ordered already.
    return "@{$(($var.Keys | foreach { "$_ = $(Quote $var.$_ -Force)" }) -join "; ")}"
  }
  if (!($ImplicitTypes -contains $type)) { # If this is not a simple type in the list above
    $values = @()
    if ($var.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) {
      # This object has explicit display properties defined. Use them.
      foreach ($name in $var.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) {
	$value = Quote $var.$name
	$values += "$name = $value"
      }
    } else { # Check if the type has a default *.ps1xml format data definition
      $fd = Get-FormatData $type # If type strings in .psTypeNames[0] and .GetType().FullName differ, it's the first one that gives good results.
      if ($fd -and $fd.FormatViewDefinition[0].control.Entries.Items) {
	# We do have a list of default fields to display. (The ones used by Out-String by default!)
	foreach ($item in $fd.FormatViewDefinition[0].control.Entries.Items) {
	  switch ($item.DisplayEntry.ValueType) {
	    "Property" {
	      $name = $item.DisplayEntry.Value
	      $value = Quote $var.$name
	    }
	    "ScriptBlock" {
	      $name = $item.Label
	      $value = Quote (eval "`$_ = `$var ; $($item.DisplayEntry.Value)")
	    }
	    "default" {
	      Write-Error "Unsupported ValueType: $($item.DisplayEntry.ValueType)"
	    }
	  }
	  $values += "$name = $value"
	}
      }
    }
    switch ($values.length) {
      0 {} # No type list found. Fall through into the [string] cast default.
      1 {return $value} # Trivial object with just one field. No need to specify type and detailed field names since conversion will be trivial.
      default {return "[$type]@{$($values -join "; ")}"} # Complex object with multiple fields. Report type and every field with a [PSCustomObject]-like syntax.
    }
    # Else let the [string] cast do the conversion
    $Force = $True # Force quotes around it, else the type cast will likely fail.
    $TypeCast = "[$type]"
  } else {
    $TypeCast = ""
  }
  $string = [string]$var # Now whatever the type, convert it to a real string
  if ($string.length -eq 0) { # Special case of the empty string
    return '""'
  }
  if ($Force -or ($string -match "[ ``""'$]")) { # If there's any character that needs quoting
    if (($string -match '"') -and !($string -match "'")) { # If there are "s and no 's
      $string = "'$string'" # Surround with 's to preserve everything else.
    } else { # Either there are 's, or there are neither 's nor "s
      $s2 = ''
      for ($i=0; $i -lt $string.length; $i++) {
	$s2 += Switch ($string.Chars($i)) {
	  '`' { '``'; } 	# Back quote
	  '$' { '`$'; } 	# Dollar sign
	  '"' { '""'; } 	# Double quote
	  "`0" { '`0'; }	# Null
	  "`a" { '`a'; }	# Alert
	  "`b" { '`b'; }	# Backspace
	  "`f" { '`f'; }	# Form feed
	  "`n" { '`n'; }	# New line
	  "`r" { '`r'; }	# Carriage return
	  "`t" { '`t'; }	# Horizontal tab
	  "`v" { '`v'; }	# Vertical tab
	  default {
	    if ($_ -lt " ") {
	      "`$([char]0x$("{0:X2}" -f [byte]$_))"
	    } else {
	      $_
	    } # For Unicode chars > 2^16, use "$([char]::ConvertFromUtf32(0xXXXXXXXX))"
	  }
	}
      }
      $string = """$s2"""
    }
  }
  return "$TypeCast$string"
}

#-----------------------------------------------------------------------------#
#                                                                             #
#   Function        Write-Vars		                                      #
#                                                                             #
#   Description     Display variables names and values, in a quoted format    #
#                                                                             #
#   Arguments       A list of variable names in the caller's scope.           #
#                                                                             #
#   Notes           The quoted format allows good readability and easy parsing#
#                                                                             #
#   History                                                                   #
#    2010-10-22 JFL Created this routine.                                     #
#    2013-10-03 JFL Renamed Write-Vars as Write-Vars.                         #
#                   Use standard Write-Xxxxx output routines.                 #
#                   Format the output as a native PowerShell assignment.      #
#    2013-11-19 JFL Detect undefined variables, and report them in a comment. #
#                                                                             #
#-----------------------------------------------------------------------------#

Function Write-Vars () {
  foreach ($name in $args) {
    try {
      $var = Get-Variable $name -Scope 1 -ea stop
    } catch {
      Write-Host "# `$$name undefined"
      continue
    }
    Write-Host "`$$name = $(Quote $var.Value -Force)"
  }
}

Function Write-DebugVars () {
  foreach ($name in $args) {
    try {
      $var = Get-Variable $name -Scope 1 -ea stop
    } catch {
      Write-Debug "# `$$name undefined"
      continue
    }
    Write-Debug "`$$name = $(Quote $var.Value -Force)"
  }
}

#-----------------------------------------------------------------------------#
#                                                                             #
#   Function        *Xml*                                                     #
#                                                                             #
#   Description     Generate XML output                                       #
#                                                                             #
#   Notes                                                                     #
#                                                                             #
#   History                                                                   #
#    2011-09-12 JFL Created these routines.                                   #
#                                                                             #
#-----------------------------------------------------------------------------#

# Convert characters illegal in an XML markup name
Function QuoteXmlName($name) {
  foreach ($pair in ("&", "&amp;"),
                    ("<", "&lt;"),
                    (">", "&gt;"),
                    ('"', "&quot;"),
                    ("'", "&apos;"),
                    (" ", "&#x20;"),
                    ("$([char]9)", "&#x09;")
  ) {
    ($c, $escape) = $pair
    $name = $name.replace($c, $escape)
  }
  return $name
}

# Convert characters illegal in an XML markup value or in character data
Function QuoteXmlValue($value) {
  foreach ($pair in ("&", "&amp;"),
                    ("<", "&lt;"),
                    (">", "&gt;"),
                    ('"', "&quot;")
  ) {
    ($c, $escape) = $pair
    $value = $value.replace($c, $escape)
  }
  return $value
}

# Convert optional attributes into a string to put in an XML start tag.
Function Hash2XmlAttributes($attributes) {
  $result = ""
  foreach ($key in $attributes.keys) {
    $value = QuoteXmlValue "$($attributes[$key])"
    $result += " $key=`"$value`""
  }
  return $result
}

#-----------------------------------------------------------------------------#
#                                                                             #
#   Function        Exec                                                      #
#                                                                             #
#   Description     Display a command, then execute it. Both steps optional.  #
#                                                                             #
#   Notes           For details about the splatting operator quirks, see:     #
#                   http://piers7.blogspot.com/2010/06/splatting-hell.html    #
#                                                                             #
#   History                                                                   #
#    2010-06-03 JFL Created this routine.                                     #
#                                                                             #
#-----------------------------------------------------------------------------#

Function Exec([string]$cmd) {
  $txtLine = "$cmd"
  $cmdLine = "$cmd"
  $a = $args # Make a copy (Necessary because Invoke-Expression overwrites $args)
  $n = 0
  foreach ($arg in $args) { # Parse all optional arguments following the command name.
    $txtLine += " $(Quote $arg)"
    if (($arg -ne $null) -and ($arg.GetType().FullName -eq "System.String") -and ($arg -match '^-\w+:?$')) {
      $cmdLine += " $arg" # Let Invoke-Expression decide whether it's a param name or an actual string.
    } else {
      $cmdLine += " `$a[$n]" # Preserve the type through Invoke-Expression.
    }
    $n += 1
  }
  if ($script:Verbose -or $script:NoExec) {
    Write-Host $txtLine
  }
  if (!$script:NoExec) {
    Invoke-Expression $cmdLine
  }
}

#-----------------------------------------------------------------------------#
#                                                                             #
#   Function        Put-Value		                                      #
#                                                                             #
#   Description     Display a name/value pair, in a quoted format             #
#                                                                             #
#   Notes           The quoted format allows good readability and easy parsing#
#                                                                             #
#   History                                                                   #
#    2010-05-12 JFL Created this routine.                                     #
#    2011-09-12 JFL Added native XML output option.                           #
#                                                                             #
#-----------------------------------------------------------------------------#

$currentIndent = 0

Function Put-Value (
  $name,					# The variable name
  $value,					# The variable value
  $attributes = @{},				# Optional attribute values
  [alias("i")]$indent = $script:currentIndent,	# Optional switch overriding the default indentation
  [alias("w")]$nameWidth = 0			# Optional switch specifying the name output width
) {
  if ($value -eq $null) {
    return
  }
  $spaces = "{0,$indent}" -f ""
  $attrs = Hash2XmlAttributes $attributes
  if (!$script:XML) {
    $name = Quote $name
    if ($nameWidth -ne 0) {$name = "{0,$(-$nameWidth)}" -f $name}
    $value = Quote $value
    echo "$spaces$name$attrs $value"
  } else {
    $name1 = $name2 = QuoteXmlName $name
    if ($nameWidth -ne 0) {$name1 = "{0,$(-$nameWidth)}" -f $name1}
    echo "$spaces<$name1$attrs>$value</$name2>"
  }
}

#-----------------------------------------------------------------------------#
#                                                                             #
#   Function        Put-Dir		                                      #
#                                                                             #
#   Description     Display a directory name, and open an indented block      #
#                                                                             #
#   Arguments       Name        Directory name. Required.                     #
#                   Attributes  Attributes. Optional hashtable.               #
#                   Block       ScriptBlock. Optional, must be last.          #
#                                                                             #
#   Notes           Invoke with . Put-Dir if the script block sets variables  #
#                   in the the caller's context.                              #
#                   Side effect: . invoking this script block erases the      #
#                   caller's variables $args, $putDirName, $putDirBlock,      #
#                   and $putDirSpaces.                                        #
#                                                                             #
#   History                                                                   #
#    2010-05-12 JFL Created this routine.                                     #
#    2011-09-12 JFL Added native XML output option.                           #
#                                                                             #
#-----------------------------------------------------------------------------#

Function Put-Dir(
  $putDirName				# The directory name
) {
  $l = $args.length
  $putDirAttributes = @{}		# Optional attributes
  [ScriptBlock]$putDirBlock = $null	# Optional script block that will be indented, then closed.
  if ($l) {
    $putDirBlock = $args[--$l];
  }
  if ($l) {
    $putDirAttributes = $args[--$l];
  }
  $PutDirAttrs = Hash2XmlAttributes $putDirAttributes
  $putDirSpaces = "{0,$($script:currentIndent)}" -f ""
  if (!$script:XML) {
    echo "$putDirSpaces$(Quote $putDirName)$PutDirAttrs {"
  } else {
    $putDirName = QuoteXmlName $putDirName
    echo "$putDirSpaces<$putDirName$PutDirAttrs>"
  }
  $script:currentIndent += 2
  if ($putDirBlock -ne $null) {
    . $putDirBlock # Execute the ScriptBlock in our own scope
    # Note: Do not reuse local variables now on, as recursive . Put-Dir inclusion will overwrite them!
    Put-EndDir $putDirName
  }
}

Function Put-EndDir(
  $putDirName				# The directory name
) {
  $script:currentIndent -= 2
  $spaces = "{0,$($script:currentIndent)}" -f ""
  if (!$script:XML) {
    echo "$spaces}"
  } else {
    echo "$spaces</$putDirName>"
  }
}

#-----------------------------------------------------------------------------#
#                                                                             #
#   Function        Put-Vars		                                      #
#                                                                             #
#   Description     Display variables names and values, in a quoted format    #
#                                                                             #
#   Arguments       A list of variable names in the caller's scope.           #
#                                                                             #
#   Notes           The quoted format allows good readability and easy parsing#
#                                                                             #
#   History                                                                   #
#    2010-10-22 JFL Created this routine.                                     #
#                                                                             #
#-----------------------------------------------------------------------------#

Function Put-Vars () {
  foreach ($name in $args) {
    $var = Get-Variable $name -Scope 1
    Put-Value $name $var.Value
  }
}

#-----------------------------------------------------------------------------#
#                                                                             #
#   Function        Get-RegistryValue                                         #
#                                                                             #
#   Description     Get a registry value                                      #
#                                                                             #
#   Notes           Return $null if the key/value does not exist.             #
#                                                                             #
#   History                                                                   #
#    2010-05-12 JFL Created this routine.                                     #
#                                                                             #
#-----------------------------------------------------------------------------#

Function Get-RegistryValue($key, $name) {
  Write-Debug "Get-RegistryValue(`"$key`", `"$name`")"
  $item = Get-ItemProperty -ErrorAction SilentlyContinue $key
  if ($item) {
    return $item.$name
  } else {
    return $null
  }
}

#-----------------------------------------------------------------------------#
#                                                                             #
#   Function        Get-SMBiosStructures                                      #
#                                                                             #
#   Description     Get the system GUID                                       #
#                                                                             #
#   Returns         An array of SMBIOS structures of the requested type.      #
#                                                                             #
#   Notes           Use mssmbios.sys copy of the SMBIOS table in the registry.#
#                   Documented as unreliable, but available in WinXP ... Win7.#
#                                                                             #
#                   Some fields, like the UUID in structure 1, are cleared    #
#                   for "Security Reasons".                                   #
#                                                                             #
#		    An alternative would be to use property SmBiosData in WMI #
#		    class MSSMBios_RawSMBiosTables in WMI name space root\wmi.#
#                                                                             #
#   History                                                                   #
#    2010-06-08 JFL Created this routine.                                     #
#                                                                             #
#-----------------------------------------------------------------------------#

Function Get-SMBiosStructures($Type) {
  Write-Debug "Get-SMBiosStructures($Type)"
  $structs = @()
  $key = "HKLM:\SYSTEM\CurrentControlSet\services\mssmbios\Data"
  if (!(Test-Path $key)) {
    Write-Debug "No SMBIOS table copy found in the registry"
    return $null
  }
  $data = Get-RegistryValue $key SMBiosData
  $i = 8 # CIM structures begin at offset 8
  while (($data[$i+1] -ne $null) -and ($data[$i+1] -ne 0)) { # While the structure has non-0 length
    $i0 = $i
    $n = $data[$i]   # Structure type
    $l = $data[$i+1] # Structure length
    Write-Debug "Skipping structure $n body"
    $i += $l # Skip the structure body
    if ($data[$i] -eq 0) {$i++} # If there's no trailing string, skip the extra NUL
    while ($data[$i] -ne 0) { # And skip the trailing strings
      $s = ""
      while ($data[$i] -ne 0) { $s += [char]$data[$i++] }
      Write-Debug "Skipping string $s"
      $i++ # Skip the string terminator NUL
    }
    $i1 = $i
    $i++ # Skip the string list terminator NUL
    if ($n -eq $Type) {
      $structs += ,@($data[$i0..$i1])
    }
  }
  return @($structs)
}

Function Get-SMBiosStructureString($Struct, $Index) {
  Write-Debug "Get-SMBiosStructureString($Struct, $Index)"
  if ($Index -le 0) {
    return $null # Undefined string
  }
  $i = $Struct[1] # Skip the structure body
  if ($Struct[$i] -eq 0) {$i++} # If there's no trailing string, skip the extra NUL
  while ($Struct[$i] -ne 0) { # While there are more strings
    $s = ""
    while ($Struct[$i] -ne 0) { $s += [char]$Struct[$i++] }
    if (--$Index -eq 0) {
      return $s # Found!
    }
    $i++ # Skip the string terminator NUL
  }
  return $null # String not found
}

#-----------------------------------------------------------------------------#
#                                                                             #
#   Function        ConvertTo-ISODate                                         #
#                                                                             #
#   Description     Convert a date to the ISO 8601 format                     #
#                                                                             #
#   Notes                                                                     #
#                                                                             #
#   History                                                                   #
#    2010-10-19 JFL Created this routine.                                     #
#    2010-06-02 JFL Fixed quotes, which caused errors in Korean Windows.      #
#    2010-09-27 JFL Renamed variable Date as Date1 to avoid conflicting with  #
#                   SubVersion Date keyword.                                  #
#                                                                             #
#-----------------------------------------------------------------------------#

function ConvertTo-ISODate {
  param(
    [Parameter(Position = 0, ValueFromPipeLine = $true)]
    [DateTime]
    $Date1 = [DateTime]::Today
  )
  process {
    # output the ISO week date
    return '{0:0000}-{1:00}-{2:00}' -f $Date1.Year, $Date1.Month, $Date1.Day
  }
}

#-----------------------------------------------------------------------------#
#                                                                             #
#   Function        GetSystemInformation                                      #
#                                                                             #
#   Description     Get the computer system information (Bios, iLO, enclosure)#
#                                                                             #
#   Notes                                                                     #
#                                                                             #
#   History                                                                   #
#    2011-08-16 JFL Created this routine from code in the main routine.       #
#                                                                             #
#-----------------------------------------------------------------------------#

function GetSystemInformation {
  # Get the computer name
  Try {
    # 2011-09-19 JFL Use WMI to get the computer name and domain
    $computer = Get-WmiObject -Class Win32_ComputerSystem
    # $name = $env:COMPUTERNAME.ToLower()
    # $domain = $env:USERDNSDOMAIN.ToLower() ; # Depends on login!
    $name = $computer.name.ToLower()
    $domain = $computer.domain.ToLower()
  } Catch {}

  # Get the computer model
  Try {
    $CompInfo = get-wmiobject -class "MS_SystemInformation" -namespace "root\WMI" -EA $WmiEA
    $CompMaker = $CompInfo.SystemManufacturer -replace "Hewlett.Packard", "HP"
    $CompModel = $CompInfo.SystemProductName -replace "Hewlett.Packard", "HP"
    $Struct1 = Get-SMBiosStructures 1
    $SKUindex = $Struct1[25] # "SKU Number" string index
    $CompSKU = Get-SMBiosStructureString $Struct1 $SKUindex
    $CompSKU = $CompSKU.Trim()
    $SysModel = $E5000Models[$CompSKU] # Convert the E5000 blade SKU to a system product name
    if ($SysModel -eq $null) { $SysModel = $X5000Models[$CompSKU] } # Convert the X5000 blade SKU to a system product name
    # Alternative tested, but eliminated as it's the same as $CompModel:
    # if ($SysModel -eq $null) { $SysModel = Get-SMBiosStructureString $Struct1 $Struct1[5] } # Get the SMBIOS computer product name
  } Catch { Write-Debug "computer: $($error[0])" }

  # Get the position in the enclosure
  $Location = get-wmiobject -class "HP_BladeCSLocation" -namespace "root\HPQ" -EA $WmiEA
  $bay = $null
  if ($Location) {
    $bay = $Location.PhysicalPosition
  }

  # Get the BIOS version
  Try {
    $Bios = get-wmiobject -class "Win32_BIOS" -namespace "root\CIMV2" -EA $WmiEA
    # Note: The BIOSVersion field does not report a correct value.
    $BiosVersion = $Bios.SMBIOSBIOSVersion
    $BiosDate = $Bios.ReleaseDate # The date does not look friendly.
    $BiosDate = $BiosDate.Substring(0,4) + "-" + $BiosDate.Substring(4,2) + "-" + $BiosDate.Substring(6,2)
  } Catch { Write-Debug "bios: $($error[0])" }

  # Report computer information
  Put-Dir computer {
    Put-value -w 6 model  ("$CompMaker $CompModel" -replace "^$CompMaker $CompMaker", "$CompMaker")
    Put-value -w 6 sku    $CompSKU
    Put-value -w 6 system $SysModel
    Put-Value -w 6 name   $name
    Put-Value -w 6 domain $domain
    Put-value -w 6 bay    $bay
    Put-value -w 6 bios   $BiosVersion
    Put-value -w 6 date   $BiosDate
  }

  # Get the iLO information
  Try {
    $iLO = get-wmiobject -class "HP_ManagementProcessor" -namespace "root\HPQ" -EA $WmiEA
    $iLOtype = $iLO.ElementName
    $iLOname = $iLO.HostName
    $iLOip = $iLO.IPAddress
  } Catch { Write-Debug "iLO method 1: $($error[0])" }
  Try {
    $iLOFW = get-wmiobject -class "HP_MPFirmware" -namespace "root\HPQ" -EA $WmiEA
    $iLOversion = $iLOFW.VersionString
    $iLOrelease = $iLOFW.ReleaseDate
    $iLOdate = $iLOrelease.Substring(0,4) + "-" + $iLOrelease.Substring(4,2) + "-" + $iLOrelease.Substring(6,2)
  } Catch { Write-Debug "iLO method 2: $($error[0])" }
  if ($iLO) {
    Put-Dir ilo {
      Put-Value -w 5 model $iLOtype
      Put-Value -w 5 name  $iLOname
      Put-Value -w 5 ip    $iLOip
      Put-Value -w 5 fw    $iLOversion
      Put-Value -w 5 date  $iLOdate
    }
  }

  # Get the power management controller information
  Try {
    $pmc = get-wmiobject -class "HP_PowerControllerFirmware" -namespace "root\HPQ" -EA $WmiEA
    $pmcModel = ($pmc.IdentityInfoValue[0] -replace "^HPQ:", "") -replace "-", " "
    if ($pmcModel -eq "Unknown") { $pmcModel = $pmc.Name }
    $pmcVersion = $pmc.VersionString
  } Catch { Write-Debug "Power Management Controller: $($error[0])" }
  if ($pmc) {
    Put-Dir pmc {
      Put-Value -w 5 model $pmcModel
      Put-Value -w 5 fw    $pmcVersion
    }
  }

  # Get enclosure information
  Try {
    $Enclosure = get-wmiobject -class "HP_BladeEnclosureCS" -namespace "root\HPQ" -EA $WmiEA
    $EncName = $Enclosure.Name
    $EncIp = $Enclosure.ManagementIPAddress
    $EncType = $Enclosure.Model # The normal model name for CSP enclosures
    $EncOther = $Enclosure.OtherIdentifyingInfo[1] # An alternate model name.
    if ($EncOther) { $EncOther = $EncOther -replace ":.*","" } # Remove the serial number suffix
    if (($EncType -eq $null) -and ($EncOther -ne $null)) { # C7000 blade systems only have that alternate model name set.
      $EncType = $EncOther;
      $EncOther = $null
    }
  } Catch { Write-Debug "enclosure method 1: $($error[0])" }
  Try {
    $EnclosureFW = get-wmiobject -class "HP_BladeEnclosureFW" -namespace "root\HPQ" -EA $WmiEA
    $EncFwName = $EnclosureFW.ElementName
    $EncFwVersion = $EnclosureFW.VersionString
  } Catch { Write-Debug "enclosure method 2: $($error[0])" }
  Try {
    # ssh to the EM. Authentication will fail, but we'll have captured the greeting string.
    # Use BatchMode=yes to avoid getting prompted for a password.
    # Use StrictHostKeyChecking=no to avoid getting an error if the EM key has changed after a previous FW upgrade.
    $EncGreeting = ssh -o "BatchMode=yes" -o "StrictHostKeyChecking=no" $EncIp 2>&1
    if ("$EncGreeting" -match "`nDate: (\S+)") {
      $EncFwDate = ConvertTo-ISODate $Matches[1]
    }
    if ("$EncGreeting" -match "`nSVN Version: (\S+)") {
      $EncSvnVer = $Matches[1]
    }
  } Catch { Write-Debug "enclosure method 3: $($error[0])" }
  $cmpLib = "C:\ProgramData\Hewlett-Packard\CMP\shared\lib"
  if (($EncSvnVer -eq $null) -and (Test-Path $cmpLib)) {
    # Idem, but using CMP's Java object
    $oldDir = Get-Location
    Try {
      Set-Location $cmpLib
      # 2011-04-14 JFL cmp-common.jar now replaced by cmp-common-1.0.1.jar, without a symlink.
      #                So for earch jar, search for the version-less symlink first,
      #                then for the versioned .jar. (Any version will do)
      $cmp_common_jar = "cmp-common.jar"
      if (!(Test-Path $cmp_common_jar)) {
	foreach ($jar in dir cmp-common-*.jar) { $cmp_common_jar = $jar.Name; break }
      }
      $log4j_jar = "log4j.jar"
      if (!(Test-Path $log4j_jar)) {
	foreach ($jar in dir log4j-*.jar) { $log4j_jar = $jar.Name; break }
      }
      $EncInfo = java -classpath "$cmp_common_jar;$log4j_jar;" "com.hp.usd.cmp.common.cli.EmFlash" 2>&1
      if ("$EncInfo" -match "Firmware Ver. : (EM: )?(\S+) (\S+\s+\S+\s+\d+)") {
	$EncFwDate = ConvertTo-ISODate $Matches[3]
      }
      if ("$EncInfo" -match ": SVN: (\d+)") {
	$EncSvnVer = $Matches[1]
      }
    } Catch {
      Write-Debug "enclosure method 4: $($error[0])"
    } Finally {
      Set-Location $oldDir
    }
  }
  if ($Enclosure) {
    Put-Dir enclosure {
      Put-Value -w 5 model $EncType
      if ($Verbose) {Put-Value -w 5 other $EncOther}
      Put-Value -w 5 name  $EncName
      Put-Value -w 5 ip    $EncIp
      Put-Value -w 5 fw    $EncFwVersion
      Put-Value -w 5 date  $EncFwDate
      Put-Value -w 5 svn   $EncSvnVer
    }
  }
}

#-----------------------------------------------------------------------------#
#                                                                             #
#   Function        GetStorageControllersInformation                          #
#                                                                             #
#   Description     Get storage controllers information                       #
#                                                                             #
#   Notes                                                                     #
#                                                                             #
#   History                                                                   #
#    2011-08-16 JFL Created this routine from code in the main routine.       #
#    2011-11-18 JFL Added the controller cache size.                          #
#    2015-10-09 JFL Fixed disk index numbers; Specify the disk port and box.  #
#                   Changed disk size to an integer number of gigabytes.      #
#                                                                             #
#-----------------------------------------------------------------------------#

function GetStorageControllersInformation {
  Try {
    # 2011-09-19 JFL Use WMI to get the computer name and domain
    $Ctrls = @(get-wmiobject -class "Win32_SCSIController" -namespace "root\CIMV2" -EA $WmiEA)
  } Catch { Write-Debug "Enum win32 scsi: $($error[0])" }
  if ($Ctrls) {
    Put-Dir scsi {
      # Get the internal controller information
      Try { # First try using HP's WMI extension classes
	$HpCtrls = @(get-wmiobject -class "HPSA_ArraySystem" -namespace "root\HPQ" -EA $WmiEA)
	foreach ($Ctrl in $HpCtrls) {
	  $CtrlName = $Ctrl.Name
	  $CtrlType = $Ctrl.ElementName -replace " in [sS]lot \d+",""
	  $CtrlFwFilter = "InstanceID like '%:$CtrlName'"
	  $CtrlFW = get-wmiobject -class "HPSA_Firmware" -namespace "root\HPQ" -filter "$CtrlFwFilter" -EA $WmiEA
	  $CtrlFwVersion = $CtrlFW.VersionString
	  # While at it, check if a cache is present, and get its size
	  Try {
	    $CtrlFilter = "Name='$CtrlName'"
	    $Ctrl2 = get-wmiobject -class "HPSA_ArrayController" -namespace "root\HPQ" -filter "$CtrlFilter" -EA $WmiEA
	    if ($Ctrl2.CacheSizeTotal) {
	      $CtrlCacheSize = $Ctrl2.CacheSizeTotal / (1024*1024)
	    } else {
	      $CtrlCacheSize = 0
	    }
	  } Catch {} 
	  if ($CtrlType) {
	    # Generate the 1-word name from the type string. Known examples:
	    # p410i	"Smart Array P410i"
	    # b120i	"Dynamic Smart Array B120i RAID controller"
	    # p822	"Smart Array P822 controller"
	    $CtrlName = $CtrlType -replace "^(\D*\s)?(\S+\d+[iI]?)(\s\D*)?$", '$2'
	    Put-Dir $CtrlName.ToLower() {
	      Put-Value -w 5 model $CtrlType
	      Put-Value -w 5 fw    $CtrlFwVersion
	      if ($CtrlCacheSize -or $Verbose) {
		Put-Value -w 5 cache "${CtrlCacheSize}MB"
	      }
	    }
	  }
	}
      } Catch { Write-Debug "scsi 1 method 1: $($error[0])" }
      if (!$Ctrl) { # If this does not work, try using Win32 standard WMI objects
	foreach ($C in $Ctrls) {
	  if ($C.Name -match ".*\d+[iI] Controller") {
	    $Ctrl = $C
	    $CtrlType = $Ctrl.Name
	    if ($CtrlType) {
	      $CtrlName = $CtrlType -replace "^(\D*\s)?(\S+\d+[iI])(\s\D*)?$", '$2'
	      Put-Dir $CtrlName.ToLower() {
		Put-Value -w 5 model $CtrlType
	      }
	    }
	  }
	}
      }
  
      # Get the external (mezzanine) controller information
      $CtrlType = $null
      $CtrlFwBuild = $null
      $CpldFwVersion = $null
      Try { # First try using HP's WMI extension classes
	$Ctrl = get-wmiobject -class "HP_CCStorageController" -namespace "root\HPQ_$bay" -EA $WmiEA
	$CtrlType = $Ctrl.ElementName
	if ($CtrlType) {
	  $CtrlType = $CtrlType -replace "_"," " # Old versions of the HP code return _ instead of spaces.
	  $CtrlType = $CtrlType -replace "Controller \d of ",""
	}
	$CtrlFW = get-wmiobject -class "HP_CCStorageControllerStorageControllerFirmware" -namespace "root\HPQ_$bay" -EA $WmiEA
	$CtrlFwFilter = $CtrlFW.Antecedent -replace ".*HP_CCSoftwareIdentity.", ""
	$CtrlFW = get-wmiobject -class "HP_CCSoftwareIdentity" -namespace "root\HPQ_$bay" -filter "$CtrlFwFilter" -EA $WmiEA
	$CtrlFwVersion = $CtrlFW.VersionString
	if ($CtrlFwVersion) { $CtrlFwVersion = $CtrlFwVersion -replace "^0+", "" }
	$CtrlFwBuild = $CtrlFW.LargeBuildNumber
	} Catch { Write-Debug "scsi 2 method 1: $($error[0])" }
      if (!$CtrlFwBuild) { # If this does not fully work, try using the ccu.exe command
	Try {
	  $CtrlInfos = ccu show controller all details 2>&1
	  if (!$?) { throw "ccu error: $CtrlInfos" }
	  $CtrlInfos = [regex]::split($CtrlInfos, 'controller ')
	  $CtrlInfos = $CtrlInfos[1..10000] # Drop the first empty item
	  foreach ($CtrlInfo in $CtrlInfos) {
	    if ($CtrlInfo -match "Model: 1210m") {
	      $CtrlType = "Storage Works 1210m Controller"
	      if ($CtrlInfo -match "Firmware Version: 0*(\S+)") {
		$CtrlFwVersion = $Matches[1]
	      }
	      if ($CtrlInfo -match "Firmware Build: (\S+)") {
		$CtrlFwBuild = $Matches[1]
	      }
	      break
	    }
	  }
	} Catch { Write-Debug "scsi 2 method 2: $($error[0])" }
      }
      if ($CtrlType) { # Get the CPLD revision if possible
	Try {
	  $CpldInfo = ccu log controller local | Select-String CPLD
	  if ($CpldInfo -match "CPLD Rev being set to (\S+)") {
	    $CpldFwVersion = $Matches[1]
	  }
	} Catch { Write-Debug "scsi 2 cpld search: $($error[0])" }
      }
      if (!$CtrlType) { # If this does not work, try using Win32 standard WMI objects
	foreach ($C in $Ctrls) {
	  if ($C.Name -match ".*\d+[mM] Controller") {
	    $Ctrl = $C
	    $CtrlType = $Ctrl.Name
	    break
	  }
	}
      }
      if ($CtrlType) {
	$CtrlName = $CtrlType -replace "^(\D*\s)?(\S+\d+[mM])(\s\D*)?$", '$2'
	if ($CtrlFwBuild) {
	  $CtrlFwBuild = "$CtrlFwBuild" # Convert the number to a string
	  $CtrlFwDate = $CtrlFwBuild.Substring(0,4) + "-" + $CtrlFwBuild.Substring(4,2) + "-" + $CtrlFwBuild.Substring(6,2)
	}
	Put-Dir $CtrlName.ToLower() {
	  Put-Value -w 5 model $CtrlType
	  Put-Value -w 5 fw    $CtrlFwVersion
	  Put-Value -w 5 build $CtrlFwBuild
	  Put-Value -w 5 date  $CtrlFwDate
	  Put-Value -w 5 cpld  $CpldFwVersion
	}
      }
    } # End of scsi controllers
  }

  # Get the internal drives information
  Try { # First try using HP's WMI extension classes
    $DiskFWs = get-wmiobject -class "HPSA_DiskDriveFirmware" -namespace "root\HPQ" -EA $WmiEA
  } Catch { Write-Debug "Enumerating disks FWs: $($error[0])" }
  if ($DiskFWs -ne $null) {
    Put-Dir "disks" {
      $nDisk = 0
      foreach ($DiskFW in $DiskFWs) {
	$nDisk += 1
	$DiskFwVersion = $DiskFW.VersionString
	$DiskModel = $DiskFW.ElementName
	$DiskId = $DiskFW.InstanceID -replace ".*DiskDriveFirmware:", ""
	$DiskPort = $null
	$DiskBox = $null
	$DiskBay = $null
	$DiskSize = $null
	Try { # First try using HP's WMI extension classes
	  $Disk = get-wmiobject -class "HPSA_DiskDrive" -namespace "root\HPQ" -filter "DeviceID='$DiskId'" -EA $WmiEA
	  $DiskName = $Disk.ElementName # Ex: "Port:1I Box:1 Bay:1"
	  $DiskRpm = $Disk.DriveRotationalSpeed # Rotational speed, in RPM
	  $DiskSpeed = $Disk.NegotiatedSpeed / 1000000000 # Transfer speed, in Gbits/s
	  $Extent = get-wmiobject -class "HPSA_StorageExtent" -namespace "root\HPQ" -filter "DeviceID='$DiskId'" -EA $WmiEA
	  $DiskSize = [math]::floor(($Extent.NumberOfBlocks * $Extent.BlockSize) / 1000000000)
	} Catch { }
	if ($DiskName -match "Port:(\d+\S?)") {
	  $DiskPort = $Matches[1]
	}
	if ($DiskName -match "Box:(\d+)") {
	  $DiskBox = $Matches[1]
	}
	if ($DiskName -match "Bay:(\d+)") {
	  $DiskBay = $Matches[1]
	}
	Put-Dir "disk$nDisk" {
	  Put-Value -w 5 model $DiskModel
	  Put-Value -w 5 fw    $DiskFwVersion
	  if ($Verbose) {
	    Put-Value -w 5 port  $DiskPort
	    Put-Value -w 5 box   $DiskBox
	    Put-Value -w 5 bay   $DiskBay
	    Put-Value -w 5 size  "$($DiskSize)GB"
	    Put-Value -w 5 rpm   $DiskRpm
	    if ($DiskSpeed) {
	      Put-Value -w 5 speed "$($DiskSpeed)Gb/s"
	    }
	  }
	}
      }
    }
  }

  # Get SEP information
  Try {
    $SepInfos = ccu show seps all details 2>&1 # This returns an array of lines
    if (!$?) { throw "ccu error: $SepInfos" }
    $groups = [regex]::matches($SepInfos -join "`n",'SEP[^\n]+\n(\s+\S[^\n]+\n)*',"Multiline")
  } Catch { Write-Debug "seps: $($error[0])" }
  if ($groups) {
    Put-Dir seps {
      foreach ($group in $groups) {
	$value = $group.Value
	if ($value -match "^SEP\s+(\d+)") {
	  $type = "sep" # Generic type if we don't identify the actual type
	  if ($value -match "Model:\s+(\S+)") {
	    $type = $matches[1]
	  }
	  $index = $matches[1]
	  Put-Dir $type.ToLower() {
	    if ($value -match "SEP type:\s+([^\n]+)") {
	      Put-Value -w 5 type  $matches[1]
	    }
	    if ($value -match "Model:\s+([^\n]+)") {
	      Put-Value -w 5 model $matches[1]
	    }
	    if ($value -match "Firmware Revision:\s+([^\n]+)") {
	      Put-Value -w 5 fw    $matches[1]
	    }
	  }
	}
      }
    }
  }
}

#-----------------------------------------------------------------------------#
#                                                                             #
#   Function        GetNetworkControllersInformation                          #
#                                                                             #
#   Description     Get network controllers information                       #
#                                                                             #
#   Notes                                                                     #
#                                                                             #
#   History                                                                   #
#    2011-08-16 JFL Created this routine from code in the main routine.       #
#    2012-10-22 JFL Recognize new controllers with no NC prefix to their name.#
#    2015-10-08 JFL Rewrote these routines to be more general.                #
#                                                                             #
#-----------------------------------------------------------------------------#

function GetNetworkControllerFirmwareVersion($Guid) {
  if ($Guid -ne $Null) {
    try { # This will fail if HP WMI drivers are not loaded, and do not provide the root\HPQ namespace.
      $Firmware = @(get-wmiobject -class "HP_WinEthBootcodeVersion" -namespace "root\HPQ" -filter "InstanceID='$Guid'" -EA "SilentlyContinue")
      if (!$Firmware) { # Try this one instead. Usually one or the other is set.
	$Firmware = @(get-wmiobject -class "HP_WinEthPXEVersion" -namespace "root\HPQ" -filter "InstanceID='$Guid'" -EA "SilentlyContinue")
      }
      if ($Firmware) {
       return $Firmware[0].VersionString
      }
    } catch {}
  }
  return $Null
}

function GetNetworkControllersInformation {
  Put-Dir lan {
    # Record known controllers, to avoid listing multi-port devices multiple times
    $knownCtrls = @()
    $nPorts = @{}

    # Get the internal controller information
    $Ctrls = @(get-wmiobject -class "Win32_NetworkAdapter" -namespace "root\CIMV2" -filter "PhysicalAdapter=true" -EA $WmiEA)
    foreach ($Ctrl in $Ctrls) {
      $ProductName = $Ctrl.ProductName
      Write-Debug "# Network controller"
      Write-DebugVars ProductName
      $ShortName = $null
      $FW = $null
      # Eliminate virtual adapters
      if ($ProductName -like "*Virtual*") { # This is a VMware or Hyper-V virtual adapter, etc. Ignore it.
      	continue
      }
      # Check if we've listed it already
      if ($nPorts[$ProductName]) { # We've seen another port of this same controller already.
      	$nPorts[$ProductName] += 1
        continue
      }
      # OK, record a new controller
      $knownCtrls += $Ctrl
      $nPorts[$ProductName] = 1
    }
    # Now generate the output for all controllers
    $nCtrl = 0
    foreach ($Ctrl in $knownCtrls) {
      $ProductName = $Ctrl.ProductName
      $nCtrl += 1
      # Extract a friendly short name from the full product name
      if (    ($ProductName -match "HP (NC\d+i) .*")       <# Ex: "HP NC553i Dual Port FlexFabric 10Gb Converged Network Adapter" #> `
          -or ($ProductName -match "HP (NC\d+m) .*")       <# Ex: "HP NC382m DP 1GbE Multifunction BL-c Adapter" #> `
          -or ($ProductName -match "HPE? .*port (\S+) Adapter") <# Ex: "HP Ethernet 1Gb 4-port 366i Adapter" #> `
          -or ($ProductName -match "^\S+ (\S+) .*")        <# A non-HP device. Usually like: "Company model details..." #> `
         ) {
	$ShortName = $matches[1]
      } else { # Make up a reasonable short name
	$ShortName = "nic$nCtrl"
      }
      $FW = GetNetworkControllerFirmwareVersion $Ctrl.GUID
      Put-Dir $ShortName.ToLower() {
	Put-Value -w 5 model $ProductName
	Put-Value -w 5 fw    $FW
	if ($verbose) {
	  Put-Value -w 5 ports $nPorts[$ProductName]
	  $Speed = $ctrl.Speed
	  if ($Speed -eq 0x7FFFFFFFFFFFFFFF) { # Undefined
	    $Speed = 0
	  }
	  if ($Speed) {
	    $Speed = $Speed -replace "000000000$","Gb/s"
	    $Speed = $Speed -replace "000000$","Mb/s"
	    $Speed = $Speed -replace "000$","kb/s"
	    $Speed = $Speed -replace "(\d)$","`$1b/s"
	    Put-Value -w 5 speed $Speed
	  }
	}
      }
    }
  }
}

#-----------------------------------------------------------------------------#
#                                                                             #
#   Function        GetSoftwareInformation                                    #
#                                                                             #
#   Description     Get software information                                  #
#                                                                             #
#   Notes                                                                     #
#                                                                             #
#   History                                                                   #
#    2011-08-16 JFL Created this routine from code in the main routine.       #
#                                                                             #
#-----------------------------------------------------------------------------#

function GetSoftwareInformation() {
  # Get CCU version
  Try {
    $CcuVersion = ccu version
    $CcuName = "HP Storage Cluster Configuration Utility"
  } Catch {}

  # Scan the uninstall strings in the registry
  $apps = @()
  $appVers = @{}
  $product = $null
  $uninstallApps = dir HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
  if (dir HKLM:\SOFTWARE\Wow6432Node -EA SilentlyContinue) { # On machines that have it...
    $uninstallApps += dir HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall
  }
  foreach ($app in $uninstallApps) {
    $appName = $app.Getvalue("DisplayName")
    if ($appName -eq $null) { continue }
    $appVer = $app.Getvalue("DisplayVersion")
    if ($appVer -eq $null) { continue }
    $contact = "$($app.Getvalue('Contact'))"
    $rx = '^HP|^Hewlett-Packard|Exchange'
    if (($appName -match $rx) -or ($contact -match $rx)) {
      if (!($appName -match 'Language Pack')) {
	$apps += ,$appName
	$appVers["$appName"] = $appVer
      }
    }
    # Look for core software identifying known products
    if ($appName -match "HP (.+) Enclosure Manager Settings") {
      $product = $matches[1] # "E5000" or "X5520" or "StoreEasy 5530"
    }
    if ($appName -match "HP (.+) Storage Management Tools") {
      $product = $matches[1] # "X5520" or "StoreEasy 5530"
    }
    if ($appName -match "HP (\S+) System Manager") {
      $product = $matches[1] # "StoreEasy"
    }
    if ($appName -match ".* (StoreEasy) .*") {
      $product = $matches[1] # "StoreEasy"
    }
  }

  # Get HP Quick Restore CD software image version from the registry
  $key = "HKLM:\SOFTWARE\Wow6432Node\Wow6432Node\Hewlett-Packard\StorageWorks\QuickRestore"
  $QRVersion = Get-RegistryValue $key "QRVersion"
  if ($QRVersion -eq $null) { # Try again with a more sensible key
    $key = "HKLM:\SOFTWARE\Wow6432Node\Hewlett-Packard\StorageWorks\QuickRestore"
    $QRVersion = Get-RegistryValue $key "QRVersion"
  }
  # Build the software image name, based on the product name (if available)
  $QRName = "HP Quick Restore DVD"
  if ($product) {
    $QRName = "HP $product Quick Restore DVD"
  }

  # Get HP Service Release version from the registry
  $key = "HKLM:\Software\Hewlett-Packard\StorageServer"
  $SRVersion = Get-RegistryValue $key "SRVersion"
  if ($SRVersion -eq $null) { # Try again with an older key
    $key = "HKLM:\SOFTWARE\Wow6432Node\Wow6432Node\Hewlett-Packard\StorageWorks\QuickRestore"
    $SRVersion = Get-RegistryValue $key "SRVersion"
  }
  if ($SRVersion -eq $null) { # Try again with a more sensible key
    $key = "HKLM:\SOFTWARE\Wow6432Node\Hewlett-Packard\StorageWorks\QuickRestore"
    $SRVersion = Get-RegistryValue $key "SRVersion"
  }
  # Service Release software name
  $SRName = "HP Service Release"
  if ($product) {
    $SRName = "HP $product Service Release"
  }
  
  # Get Windows version from the registry
  $key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
  $WindowsName = Get-RegistryValue $key "ProductName"
  # (Get-Item "HKLM:SOFTWARE\Microsoft\Windows NT\CurrentVersion").GetValue("ProductName")
  Try { # Maybe there's a service pack
    $ServicePack = Get-RegistryValue $key "CSDVersion"
    if ($ServicePack -ne $null) {
      $WindowsName = "$WindowsName $ServicePack"
    }
  } Catch {}
  # Get the numeric version
  $WindowsVersion = Get-RegistryValue $key "CurrentVersion"
  $WindowsVersion += "."
  $WindowsVersion += Get-RegistryValue $key "CurrentBuild"
  # Get the localization
  $key = "HKCU:\Control Panel\International"
  $LocaleName = Get-RegistryValue $key "LocaleName"
  $WindowsName = "$WindowsName ($LocaleName)"
  $WindowsName = $WindowsName -replace '\s+', ' '
  # Get our own version
  $GetverMajor, $GetverMinor, $GetverRevision, $GetverBuild = GetVersion
  $GetverVersion = "$GetverMajor.$GetverMinor.$GetverRevision.$GetverBuild"
  $GetverName = "HP Storage SW and FW Versions List Tool"

  # Report software versions
  Put-Dir software {
    Put-Value -w 7 image $QRVersion @{name="$QRName"}
    Put-Value -w 7 sr $SRVersion @{name="$SRName"}
    Put-Value -w 7 windows $WindowsVersion @{name="$WindowsName"}
    # Note: ccu is also found as part of the registry scan below, as "DAN Cluster API".
    Put-Value -w 7 program $CcuVersion @{name="$CcuName"; cmd="ccu"}
    Put-Value -w 7 program $GetverVersion @{name="$GetverName"; cmd="getver"}
    # Sort the app names, and output versions
    foreach ($appName in ($apps | sort)) {
      Put-Value -w 7 program $appVers["$appName"] @{name="$appName"}
    }
  }
}

#-----------------------------------------------------------------------------#
#                                                                             #
#   Function        Main                                                      #
#                                                                             #
#   Description     Main routine                                              #
#                                                                             #
#   Notes           Every command that returns an array MUST be piped to ft.  #
#                   Else, subsequent requests to display a table with ft fail #
#                   with a cryptic error:                                     #
#                   "out-lineoutput : [...] is not legal or not in the        #
#                   correct sequence. This is likely caused by a user-        #
#                   specified "format-table" command which is conflicting     #
#                   with the default formatting."                             #
#                                                                             #
#   History                                                                   #
#    2010-07-29 JFL Created this routine.                                     #
#                                                                             #
#-----------------------------------------------------------------------------#

# Known E5000 and X5000 productIDs / models

$E5000Models = @{
  "631184-001" = "HP E5300 12TB Messaging System";
  "637199-001" = "HP E5500 16TB Messaging System";
  "631185-001" = "HP E5500 32TB Messaging System";
  "637200-001" = "HP E5700 40TB Messaging System";
  "631186-001" = "HP E5700 80TB Messaging System";
  "635120-001" = "HP E5700 Custom Messaging System";

  "652172-001" = "HP E5300 G2 12TB Messaging System";
  "652173-001" = "HP E5500 G2 16TB Messaging System";
  "652249-001" = "HP E5500 G2 32TB Messaging System";
  "652174-001" = "HP E5700 G2 40TB Messaging System";
  "652250-001" = "HP E5700 G2 80TB Messaging System";
  "652175-001" = "HP E5700 G2 Custom Messaging System";
}

$X5000Models = @{
  "661317-001" = "HP X5000 G2 Network Storage System";
  "706900-001" = "HP X5000 G3 Network Storage System";
}

$WmiEA = "SilentlyContinue"		# In case of error, return empty results
if ($debug) { $WmiEA = "Continue" }	# In case of error, display the error

# Return the program version, as an array of 4 numbers: $Major, $Minor, $Revision, $Build
function GetVersion() {
  foreach ($var in @("Revision", "Date")) {
    # Gotcha: Do not call variables with the SVN property name, else SVN will break it!
    New-Variable ${var}1 "" # So append a 1 to the SVN property name.
    if ($svn -match "$var\s*:\s*([^\s;$]+)") {Set-Variable ${var}1 $Matches[1]}
  }
  $Date1 = ConvertTo-ISODate $Date1
  if ($Date1 -match "(\d+)\D(\d+)\D(\d+)") {
    $Year = $matches[1]
    $Month = $matches[2]
    $Day = $matches[3]
  }
  return $Year, $Month, $Day, $Revision1
}

# If the -Version switch is specified, display the script version and exit.
if ($Version) {
  $Major, $Minor, $Revision, $Build = GetVersion
  if ($Verbose) {
    echo "$argv0 version $Major.$Minor.$Revision.$Build"
  } else {
    echo "$Major.$Minor.$Revision.$Build"
  }
  return
}

# If a remote computer name is specified, run a second instance of this script there.
if (($ComputerName -ne "localhost") -and ($ComputerName -ne ".")) {
  if ($UserName) {
    if ($Password) {
      $SSPwd = ConvertTo-SecureString -AsPlainText -Force $Password
      $cred = New-Object -typename System.Management.Automation.PSCredential -argumentlist $UserName,$SSPwd
    } else { # Else prompt for a password
      $cred = Get-Credential $UserName
    }
    Exec Invoke-Command $argv0 -ComputerName $ComputerName -Credential $cred
  } else { # Else use credentials for the current user
    Exec Invoke-Command $argv0 -ComputerName $ComputerName
  }
  return
}

# If the -System switch is specified, display the system information and exit.
if ($System) {
  GetSystemInformation # Get computer system information
  return
}

# If the -Storage switch is specified, display the storage controllers information and exit.
if ($Storage) {
  GetStorageControllersInformation # Get storage controllers information
  return
}

# If the -Network switch is specified, display the network controllers information and exit.
if ($Network) {
  GetNetworkControllersInformation # Get network controllers information
  return
}

# If the -Software switch is specified, display the software information and exit.
if ($Software) {
  GetSoftwareInformation # Get software information
  return
}

# Default: Display all known information

# Get the computer system information (Motherboard, iLO, enclosure)
GetSystemInformation

# Get storage controllers information
GetStorageControllersInformation

# Get network controllers information
GetNetworkControllersInformation

# Get software information
GetSoftwareInformation

