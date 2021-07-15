[CmdletBinding(DefaultParameterSetName = 'Ask')]
Param(
  # [String] Drive Letter, the drive which will be set up
  [Alias()][Parameter(Mandatory=$False)][String]$DriveLetter = $Null,

  # [String] Format switch, if this is true the drive will be wiped
  [Alias()][Parameter(Mandatory=$False,ParameterSetName='Format')][Switch]$Format = $False,

  # [String] Method switch, this (non-mandatory) parameter is used for the format tool
  # Method Settings: 
  # 1 - Builtin (Native) Windows Format to Fat32
  # 2 - Ridgecrop (Proprietary) Format to Fat32
  [Alias()][Parameter(Mandatory=$False)][Int]$Method = $Null,

  # [String] Update switch, if this is true the install will be updated
  [Alias()][Parameter(Mandatory=$False,ParameterSetName='Update')][Switch]$Update = $False,

  # [String] Force switch, if this is set any confirmations will be skipped
  [Alias()][Parameter(Mandatory=$False)][Switch]$Force = $False
);

Function Get-GithubRelease
{
  Param(
    # [String] [Named] Username of the github account (i.e. damon-murdoch)
    [Alias()][Parameter(Mandatory=$True,ParameterSetName='Named')][String]$UserName,

    # [String] [Named] Repository for the release (e.g. Get-3dsSd)
    [Alias()][Parameter(Mandatory=$True,ParameterSetName='Named')][String]$Repository,

    # [String] [Named] Tag for the release (e.g. Latest)
    [Alias()][Parameter(Mandatory=$False,ParameterSetName='Named')][String]$Tag = "latest",

    # [String] File Name of the file we want to download (e.g. Otherapp.bin)
    # By default, downloads all files.
    [Alias()][Parameter(Mandatory=$False)][String]$Match = $Null,

    # [String] File name of the file we want to download, as a filter. 
    # (e.g. *.exe). By default, downloads all of the files.
    [Alias()][Parameter(Mandatory=$False)][String]$Like = $Null,

    # [String] Path the file will be downloaded to
    # By default, this is the current path of the user's console
    [Alias()][Parameter(Mandatory=$False)][String]$Path = (Get-Location),

    # [String] [Url] Full URL for the release 
    # (e.g. https://api.github.com/repos/jgm/pandoc/releases/latest)
    [Alias()][Parameter(Mandatory=$True,ParameterSetName='Url')][String]$Url
  );

  Try
  {
    # If we are using the named parameter set list
    If ($PSCmdLet.ParameterSetName -eq 'Named')
    {
      # Generate the request url
      $Url = "https://api.github.com/repos/$UserName/$Repository/releases/$Tag";
    }

    # Get the result of the web request
    $Request = Invoke-WebRequest -Uri $Url;

    # If the request has a message, AND the message is 'Not Found'
    If ($Null -Ne $Request.Message -And $Request.Message -Eq "Not Found")
    {
      # Throw the failure to the handling catch
      Throw "Request Response: Not Found. Repository does not exist or does not have any releases.";
    }

    # Loop over the assets
    Foreach($Asset in $Request.Assets)
    {
      
      If (
        # If neither filters are provided OR
        (-Not $Like -And -Not $Match ) -Or 
        # If we have a match filter, and this file matches it OR
        ($Match -And $Asset.Name -Match $Match) -Or 
        # If we have a like filter, and this file matches it
        ($Like -And $Asset.Name -Like $Like)
      )
      {
        # Download the file, and save it to the specified output path
        Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile "$Path/$($Asset.name)";
      }
      Else # Filters exist, none are met
      {
        # Do not download the file
      }
    }
  }
  Catch
  {
    # Throw the failure back to the calling process
    Throw "Failed to download release! Reason: $($_.Exception.Message)";

    # Return empty array
    Return @();
  }
}

Function Format-Fat32Native
{
  Param(
    # Drive letter which is to be formatted
    [Alias()][Parameter(Mandatory=$True)][String]$DriveLetter
  );

  Try
  {
    # Clear the terminal errors
    $Error.Clear();

    # Run the native format on the drive letter
    Format /FS:FAT32 /Q /X "$($DriveLetter):";

    # If an error is reported after the script
    If ($Error.Count -Gt 0)
    {
      # Throw the error code to the calling process
      Throw "Program Reported Error Code: $LastErrorCode";
    }
  }
  Catch
  {
    Throw "Failed to format drive! Reason: $($_.Exception.Message)";
  }
}

Function Format-Fat32Ridgecrop
{
  Param(
    # Drive letter which is to be formatted
    [Alias()][Parameter(Mandatory=$True)][String]$DriveLetter, 

    # Path which the archive / exe are to be placed (if they do not exist)
    [Alias()][Parameter(Mandatory=$False)][String]$ProgramPath = $PSScriptRoot
  );

  Try
  {
    # Check to see if we already have the file
    If (-Not (Test-Path "$ProgramPath\fat32format.exe"))
    {
      # Output path for the archive
      $Archive = "$ProgramPath/fat32format.zip";

      # Download Ridgecrop fat32format.zip
      Invoke-WebRequest -Uri "http://ridgecrop.co.uk/download/fat32format.zip" -OutFile $Archive;

      # Extract the archive to fat32format.exe in the same location as the script
      Expand-Archive -Path $Archive -DestinationPath $ProgramPath;
    }

    # Clear the terminal errors
    $Error.Clear();

    # Run the Ridgecrop format tool on the sd card
    & "$ProgramPath\fat32format.exe $($DriveLetter):";

    # If an error is reported after the script
    If ($Error.Count -Gt 0)
    {
      # Throw the error code to the calling process
      Throw "Program Reported Error Code: $LastErrorCode";
    }
  }
  Catch
  {
    Throw "Failed to format drive! Reason: $($_.Exception.Message)";
  }
}

# Test the Get-GithubRelease command
# Get-GithubRelease -UserName "jgm" -Repository "pandoc" -Tag "Latest";

# This program is built upon https://3ds.hacks.guide/installing-boot9strap-(browser)

Try
{
  # Section 0 - Selecting Drive / Folder
  Try
  {
    # List the Powershell Drives
    # $Drives = Get-PSDrive -PSProvider FileSystem;
    $Drives = [System.IO.DriveInfo]::GetDrives();

    # If no drive letter is provided
    If (-Not $DriveLetter)
    {
      Write-Host "No drive selected, showing attached drives ...";

      # Loop over the drives
      Foreach($Drive in $Drives)
      {
        # If the drive is valid
        If ($Drive.TotalSize -Gt 0)
        {
          Write-Host "$($Drive.Name): $($Drive.VolumeLabel), $($Drive.DriveFormat), $([Math]::Round($Drive.TotalSize/1GB,2)) GB";
        }
      }

      # Prompt the user to provide a drive letter
      $DriveLetter = Read-Host "Please enter a drive name. (e.g. 'E:')";
    }

    # Remove ':' from the drive letter if it exists
    $DriveLetter = $DriveLetter.Replace(':','');

    # Check if the drive letter is in the list of available drive letters
    If ( -Not ($Drives | Select-Object -ExpandProperty Name).Contains("$($DriveLetter):\"))
    {
      Throw "Drive letter '$($DriveLetter):' does not exist!";
    }
    
    # Get the format of the active drive
    $DriveFormat = $Drives | Where-Object { $_.Name -Eq "$($DriveLetter):\"; } | Select-Object -ExpandProperty DriveFormat;

    Write-Host "Drive Letter '$($DriveLetter): Selected.";

    # The action which will be performed (Ask, Format, Update)
    $Action = $PSCmdlet.ParameterSetName;

    # If the user has not selected to update or format
    # an existing installation
    If ($Action -Eq "Ask")
    {
      # Prompt the user to confirm - update or format
      Write-Host "Please select an option:";
      Write-Host "1: Format $($DriveLetter): and start fresh";
      Write-Host "2: Keep existing files on $($DriveLetter): and update";

      # Read the user selection
      Switch(Read-Host "Enter Selection")
      {
        1 # Format and start fresh 
        { $Action = "Format"; }
        2 # Keep files and update 
        { $Action = "Update"; }
        default # Bad selection
        { Throw "Invalid selection: $($_)"; }
      }
    }

    # If the mode is set to update
    If ($Action -Eq "Update")
    {
      Write-Host "Update mode selected.";

      # If the drive format is NOT fat32
      If ($DriveFormat -Ne "Fat32")
      {
        # Won't work with a 3ds, throw the error to the calling process
        Throw "Drive $($DriveLetter): format must be Fat32! Current format: $($DriveFormat). Please re-run the application with the format switch, pick a different drive or format the drive to fat32 manually.";
      }
      Else
      {
        Write-Host "Drive is correct format '$($DriveFormat)', starting install ...";
      }
    }
    # If the mode is set to format
    ElseIf ($Action -Eq "Format")
    { 
      Write-Host "Format mode selected.";

      # If the force switch is NOT applied
      If (-Not $Force)
      {
        # Ask the user if they really want to format
        Write-Host "Warning: All data on drive '$($DriveLetter):' will be deleted.";
        Read-Host "Press enter to continue.";
      }

      # If force switch is NOT selected
      If (-Not $Force)
      {
        Write-Host "Please select an option:";
        Write-Host "1: Native Windows Format (slow, native)";
        Write-Host "2: Ridgecrop Format Tool (fast, proprietary)";
        $Method = Read-Host "Enter Selection";
      }
      Else
      {
        # Default to windows method
        $Method = 1;
      }

      Write-Host "Starting format.";

      # Switch on format method
      Switch($Method)
      {
        1 # Attempt to format the drive natively
        {
          Write-Host "Using native windows format ...";
          Format-Fat32Native -DriveLetter $DriveLetter; 
        }
        2 # Attempt to format the drive using ridgecrop
        { 
          Write-Host "Using ridgecrop fat32format.exe ...";
          Format-Fat32Ridgecrop -DriveLetter $DriveLetter; }
        default
        {
          Throw "Unrecognised option: '$($_)'";
        }
      }

      Write-Host "Format complete.";
    }

    # If the force switch is NOT set
    If (-Not $Force)
    {
      # Ask the user if they would like to continue
      Read-Host "Press enter to continue to the install.";
    }
    Else
    {
      Write-Output "Starting install ...";
    }

    # Get the current user location
    # Will set back to this when we are done
    $Location = Get-Location;

    # Move to the drive we are configuring
    Set-Location "$($DriveLetter):/";

  }
  Catch
  {
    Throw "Failed to select drive! Reason: $($_.Exception.Message)";
  }

  # Section 1 - Prep Work
  Try
  {
    # Step 1: Download all of the files

    # Download otherapp.bin
    Get-GithubRelease -UserName "TuxSH" -Repository "universal-otherapp" -Tag "latest" -Match "otherapp.bin" -ErrorAction Stop;

    # Download SafeBoot9StrapInstaller
    Get-GithubRelease -UserName "d0k3" -Repository "SafeB9SInstaller" -Tag "latest" -Like "SafeB9S*.zip" -ErrorAction Stop;

    # Download boot9strap
    Get-GithubRelease -UserName "SciresM" -Repository "boot9strap" -Tag "latest" -Like "boot9strap-?.?.zip" -ErrorAction Stop;

    # Download Luma3DS
    Get-GithubRelease -UserName "LumaTeam" -Repository "Luma3DS" -Tag "latest" -Like "Luma3DSv*.zip" -ErrorAction Stop;

    # Step 2: Extract and/or Copy the files

    #### OTHERAPP.BIN ####
    # Rename the otherapp binary to arm11code.bin
    Move-Item -Path "otherapp.bin" -Destination "arm11code.bin";

    #### SAFEB9INSTALLER ####
    # Extract the SafeB9Installer archive to 'SafeB9Installer'
    Expand-Archive -Path "SafeB9SInstaller-*.zip" -DestinationPath "SafeB9Installer";

    # Move the SafeB9Installer.bin to the root of the sd card
    Move-Item -Path "SafeB9Installer/SafeB9Installer.bin" -Destination ".";

    # Remove the folder from the sd card
    Remove-Item -Path "SafeB9Installer" -Recurse -Force;

    # Remove the archive from the sd card
    Remove-Item -Path "SafeB9Installer-*.zip" -Force;

    #### BOOT9STRAP #####
    # Create the boot9strap folder on the sd card
    New-Item -ItemType Directory -Path "boot9strap";

    # Extract the boot9strap archive to the current directory
    Expand-Archive -Path "boot9strap-?.?.zip" -DestinationPath "b9s";

    # Move the boot9strap.firm and boot9strap.firm.sha files to the boot9strap folder
    Move-Item -Path "b9s/boot9strap.firm*" -Destination "boot9strap";

    # Remove the folder from the sd card
    Remove-Item -Path "b9s" -Recurse -Force;

    # Remove the archive from the sd card
    Remove-Item -Path "boot9strap-?.?.zip" -Force;

    #### Luma3DS ####
    # Expand the Luma3DS archive to 'Luma3DS'
    Expand-Archive -Path "Luma3DSv*.zip" -DestinationPath "Luma3DS";

    # Move the boot.firm and boot.3dsx files to the luma3ds folder to sd root
    Move-Item -Path "Luma3DS/boot.*" -Destination ".";

    # Remove the folder from the sd card
    Remove-Item -Path "Luma3DS" -Recurse -Force;

    # Remove the archive from the sd card
    Remove-Item -Path "Luma3DSv*.zip" -Force;
  }
  Catch
  {
    Throw "Failed to perform prep work! Reason: $($_.Exception.Message)";
  }

  # Section 2 - Finalizing Setup
  Try
  {
    # Step 1: Download all of the files
    
    #### CIA / 3DSX DOWNLOAD ####
    # Create the 'cia' directory
    New-Item -ItemType Directory -Path "cia";

    # Create the '3ds' directory
    New-Item -ItemType Directory -Path "3ds";

    # Download the Anemone3DS cia / 3dsx files
    Get-GithubRelease -UserName "astronautlevel2" -Repository "Anemone3DS" -Tag "latest" -Match "Anemone3DS.cia" -Path "cia" -ErrorAction Stop;
    Get-GithubRelease -UserName "astronautlevel2" -Repository "Anemone3DS" -Tag "latest" -Match "Anemone3DS.3dsx" -Path "3ds" -ErrorAction Stop;
    
    # Download the Checkpoint cia / 3dsx files
    Get-GithubRelease -UserName "FlagBrew" -Repository "Checkpoint" -Tag "latest" -Match "Checkpoint.cia" -Path "cia" -ErrorAction Stop;
    Get-GithubRelease -UserName "FlagBrew" -Repository "Checkpoint" -Tag "latest" -Match "Checkpoint.3dsx" -Path "3ds" -ErrorAction Stop;

    # Download the Universal Updater cia / 3dsx files
    Get-GithubRelease -UserName "Universal-Team" -Repository "Universal-Updater" -Tag "latest" -Match "Universal-Updater.cia" -Path "cia" -ErrorAction Stop;
    Get-GithubRelease -UserName "Universal-Team" -Repository "Universal-Updater" -Tag "latest" -Match "Universal-Updater.3dsx" -Path "3ds" -ErrorAction Stop;

    # Download the Homebrew Launcher cia file
    Get-GithubRelease -UserName "mariohackandglitch" -Repository "homebrew_launcher_dummy" -Tag "latest" -Match "Homebrew_Launcher.cia" -Path "cia" -ErrorAction Stop;

    # Download the ctr no timeoffset 3dsx file
    Get-GithubRelease -UserName "ihaveamac" -Repository "ctr-no-timeoffset" -Tag "latest" -Match "ctr-no-timeoffset.3dsx" -Path "3ds" -ErrorAction Stop;

    # Download the DSP1 cia / 3dsx files
    Get-GithubRelease -UserName "zoogie" -Repository "DSP1" -Tag "latest" -Match "DSP1.cia" -Path "cia" -ErrorAction Stop;
    Get-GithubRelease -UserName "zoogie" -Repository "DSP1" -Tag "latest" -Match "DSP1.3dsx" -Path "3ds" -ErrorAction Stop;

    # Download the FBI cia / 3dsx files
    Get-GithubRelease -UserName "Steveice10" -Repository "FBI" -Tag "latest" -Match "FBI.cia" -Path "cia" -ErrorAction Stop;
    Get-GithubRelease -UserName "Steveice10" -Repository "FBI" -Tag "latest" -Match "FBI.3dsx" -Path "3ds" -ErrorAction Stop;

    #### DOWNLOAD AND INSTALL GODMODE9 ####
    # Download the GodMode9 Zip Archive
    Get-GithubRelease -UserName "d0k3" -Repository "GodMode9" -Tag "latest" -Like "GodMode9-v*.zip" -ErrorAction Stop;

    # Create the directory /luma/payloads
    # This will also create the luma folder if it does not exist
    New-Item -ItemType Directory -Path "luma/payloads";

    # Extract the GodMode9 archive to 'GodMode9'
    Expand-Archive -Path "GodMode9-v*" -DestinationPath "GodMode9";

    # Move the GodMode9.firm file to /luma/payloads
    Move-Item -Path "GodMode9/GodMode9.firm" -Destination "luma/payloads";

    # Move the GodMode9 folder to the root of the SD card
    Move-Item -Path "GodMode9/gm9" -Destination ".";

    # Remove the folder from the sd card
    Remove-Item -Path "GodMode9" -Recurse -Force;

    # Remove the archive from the sd card
    Remove-Item -Path "GodMode9-v*.zip" -Force;
  }
  Catch
  {
    Throw "Failed to finalise setup! Reason: $($_.Exception.Message)";
  }

  Write-Output "SD Card Configuration Complete";
  Write-Output "Please safely eject the media ($($DriveLetter):) and insert it back into your 3DS.";

  Write-Output "For the on-console steps, please follow the following guide:";
  Write-Output "https://3ds.hacks.guide/";
  Write-Output "Thanks for using the 3ds SD configuration script!";

  # Revert back to the user's original location
  Set-Location $Location;
}
Catch
{
  Write-Host "Setup Failed! Reason: $($_.Exception.Message)";
}