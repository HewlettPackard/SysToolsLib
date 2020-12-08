HPE System Tools Library
========================

This repository contains HPE-specific system management tools that were left out of the general purpose
 [System Tools Library](https://github.com/JFLarvoire/SysToolsLib).

| Tool                    | Description                                                     |
| ----------------------- | --------------------------------------------------------------- |
| Get-SmartUpdateInfo.ps1 | Display information about HPE Smart Updates CPnnnnnn.EXE. |
| GetVer.ps1              | Display the versions of all HP and HPE hardware and software on the system.   |

All tools support the -? option for getting help.


Get-SmartUpdateInfo.ps1
-----------------------

Smart Updates, also known as Smart Components, are standalone executable files with firmware, driver, or software updates.
They are distributed in Service Packs for ProLiant (SPP), and more generally on the support.hpe.com web site,
in the Drivers and Software area for each product. They're smart in the sense that they have built-in logic for
deciding if the update is necessary or not on the current system.  
The smart updates for Windows have a name like cpNNNNNN.exe, with NNNNNN a unique number identifying the update.

The problem with Smart Updates is that when you have a large collection of them, as in a SPP, or maybe in a private
repository of your own, it is hard to identify which Smart Update does what. For example, in the 2016-10 SPP, the
swpackages directory contains 858 such cp*.exe files.

Get-SmartUpdateInfo.ps1 is a PowerShell script that extracts the built-in XML meta data of cp*.exe files, and displays
it as standard PowerShell lists or tables. This allows to use all the formidable formating and filtering abilities
of PowerShell to find the Smart Update you need.

Example displaying the properties for one update:

    Get-SmartUpdateInfo.ps1 cp040096.exe
    Get-SmartUpdateInfo.ps1 cp040096.exe | fl *

Output:

    PS F:\Library\Firmware\bios> Get-SmartUpdateInfo.ps1 cp040096.exe
    
    Name     Content                                                                            Version    Date
    ----     -------                                                                            -------    ----
    cp040096 Online ROM Flash Component for Windows x64 - HP ProLiant DL380p Gen8 (P70) Servers 2019.05.24 2019-07-06
    
    
    PS F:\Library\Firmware\bios> Get-SmartUpdateInfo.ps1 cp040096.exe | fl *
    
    
    Category     : BIOS - System ROM
    Description  : This component provides updated system firmware that can be installed directly on supported Operating
                   Systems.  Additionally, when used in conjunction with Smart Update Manager (SUM), this Component allows
                   the user to update firmware on remote servers from a central location. This remote deployment
                   capability eliminates the need for the user to be physically present at the server in order to perform
                   a firmware update.
    FileName     : F:\Library\Firmware\bios\cp040096.exe
    Version      : 2019.05.24
    Content      : Online ROM Flash Component for Windows x64 - HP ProLiant DL380p Gen8 (P70) Servers
    Name         : cp040096
    Languages    : en
    Date         : 2019-07-06
    Manufacturer : Hewlett Packard Enterprise
    
    
    
    PS F:\Library\Firmware\bios>

Examples displaying in list or table format the meta-data of all Smart Updates in the current directory:

    Get-SmartUpdateInfo.ps1 cp*.exe
    Get-SmartUpdateInfo.ps1 cp*.exe | fl
    Get-SmartUpdateInfo.ps1 cp*.exe | ft -a

Another example using filtering to select BIOS related Smart Updates:

    dir cp*.exe | Get-SmartUpdateInfo.ps1 | where {$_.category -like "BIOS*"}

This will output something like:

    Name     Content
    ----     -------
    cp033181 Online ROM Flash Component for Windows x64 - HPE Apollo 4510 Gen10/HPE ProLiant XL450 Gen10 (U40) Servers
    cp033389 Online ROM Flash Component for Windows x64 - HPE ProLiant ML110 Gen10 (U33) Servers
    cp033393 Online ROM Flash Component for Windows x64 - HPE Apollo 2000 Gen10/HPE ProLiant XL170r/XL190r Gen10 (U38) S...
    etc...

It is then easy to find the exact one you need.


GetVer.ps1
----------

This script displays the versions of all HP and HPE hardware and software on the system.  
The output is formatted in an easy to read structured format called [SML](https://www.tclcommunityassociation.org/wub/proceedings/Proceedings-2013/JeanFrancoisLarvoire/A%20simpler%20and%20shorter%20representation%20of%20XML%20data%20inspired%20by%20Tcl.pdf).   
To further process the output, use the -xml option, to output the same data formatted as XML instead.

Sample output:

    computer {
      model  "HP X5460sb G2 Ntwk Stor Blade"
      sku    706900
      name   idpk1
      domain lab.gre.hp.com
      bay    1
      bios   I27
      date   2018-02-22
    }
    ilo {
      model "Integrated Lights Out 3 (iLO3)"
      name  idpk1-ilo
      ip    10.16.129.37
      fw    1.92
      date  2020-04-22
    }
    pmc {
      model "PowerPIC G2 Ntwk Stor Blade"
      fw    1.6
    }
    enclosure {
      model "HP 16LFF BACKPLANE      "
      name  idpk-em
      ip    10.16.129.13
      fw    1.50
      date  2014-08-04
      svn   20535
    }
    scsi {
      p410i {
        model "Smart Array P410i"
        fw    6.64
      }
      1210m {
        model "Storage Works 1210m Controller"
        fw    1.78
        build 2013071101
        date  2013-07-11
        cpld  0xc
      }
    }
    disks {
      disk1 {
        model "HP      EG0300FAWHV"
        fw    HPDD
      }
      disk2 {
        model "HP      EG0300FBDBR"
        fw    HPDA
      }
    }
    seps {
      ee {
        model "EE 999999"
        fw    1.8.0.28
      }
      ie {
        model "IE 999999"
        fw    1.8.0.28
      }
      ee {
        model "EE 999999"
        fw    1.8.0.28
      }
      ie {
        model "IE 999999"
        fw    1.8.0.28
      }
    }
    lan {
      nc382m {
        model "HP NC382m DP 1GbE Multifunction BL-c Adapter"
        fw    5.2.3
      }
      nc553i {
        model "HP NC553i Dual Port FlexFabric 10Gb Converged Network Adapter"
        fw    11.1.183.23
      }
      nc365t {
        model "HP NC365T PCIe Quad Port Gigabit Server Adapter"
      }
    }
    software {
      image   name="HP StoreEasy Quick Restore DVD" 4.01.0a.22
      sr      name="HP StoreEasy Service Release" 2017.05.5
      windows name="Windows Storage Server 2012 R2 Standard (en-US)" 6.3.9600
      program name="HP Storage Cluster Configuration Utility" cmd="ccu" 2.5.12539
      program name="HP Storage SW and FW Versions List Tool" cmd="getver" 2015.10.09.1468
      program name="Alert_Email_Provider" 1.0.0
      program name="AlertEmail" 1.0.0
      program name="EMIPMonitor" 1.3.0
      program name="Hewlett-Packard CMP" 2.00.15013
      program name="Hewlett-Packard CMP - Firmware Module" 2.00.22333
      program name="HP Array Configuration Utility (64-bit)" 9.40.12.0
      program name="HP Array Configuration Utility CLI (64-bit)" 9.40.12.0
      program name="HP CMP Hardware Diagnostics tool" 1.0.3
      program name="HP DAN Cluster API" 2.5.12539
      program name="HP Insight Management CSP WBEM Providers for Windows" 3.0.0.3
      program name="HP Lights-Out Online Configuration Utility" 4.8.0.0
      program name="HP Management Web Services" 1.1.0.220
      program name="HP NAS Online Help" 1.4.0
      program name="HP Pool Manager Provider" 1.1.0000
      program name="HP ProLiant Health Monitor Service (X64)" 3.20.0.0
      program name="HP ProLiant iLO 3 WHEA Driver (X64)" 3.0.0.0
      program name="HP ProLiant iLO 3/4 Channel Interface Driver" 3.10.0.0
      program name="HP ProLiant iLO 3/4 Management Controller Package" 3.20.0.0
      program name="HP ProLiant iLO CHIF Driver (X64)" 3.10.0.0
      program name="HP ProLiant iLO Core Driver (X64)" 3.9.0.0
      program name="HP RemoteSync Service" 1.5.0
      program name="HP Server Manager Extensions" 1.1.0.11
      program name="HP Smart Array SAS/SATA Event Notification Service" 6.46.0.64
      program name="HP Smart Storage Administrator" 2.40.13.0
      program name="HP Smart Storage Administrator CLI" 2.40.13.0
      program name="HP Storage Viewer" 1.3.0
      program name="HP StoreEasy 5000 Firmware Update Package" 001.008.1503.21
      program name="HP StoreEasy 5000 Firmware Update Package" 001.008.1503.21
      program name="HP StoreEasy 5530 Enclosure Manager Settings" 1.3.0
      program name="HP StoreEasy ICT" 3.0.1
      program name="HP StoreEasy PoolManager" 1.1.0.178
      program name="HP StoreEasy Storage Management Provider" 1.1.0
      program name="HP Version Control Agent" 7.2.0.0
      program name="HPE Insight Management Agents" 10.60.0.0
      program name="HPE Insight Management WBEM Providers" 10.60.0.0
      program name="HPE Insight Management WBEM Providers for Windows Server x64 Editions" 10.60.0.0
      program name="HPE System Management Homepage" 7.6.0
      program name="HPWitnessDisk " 1.0.0
    }
