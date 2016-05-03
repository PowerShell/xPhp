# Composite configuration to install the IIS pre-requisites for php
Configuration IisPreReqs_php
{
    param (
        [Parameter(Mandatory = $true)]
        [Validateset("Present","Absent")]
        [String] $Ensure
    )    

    foreach ($feature in @("Web-Server", "Web-Mgmt-Tools", "Web-Default-Doc", `
            "Web-Dir-Browsing", "Web-Http-Errors", "Web-Static-Content", `
            "Web-Http-Logging", "Web-Stat-Compression", "Web-Filtering", `
            "Web-CGI", "Web-ISAPI-Ext", "Web-ISAPI-Filter"))
    {
        WindowsFeature "$feature$Number"
        {
            Ensure = $Ensure
            Name = $feature
        }
    }
}

# Composite configuration to install PHP on IIS
Configuration xPhpProvision
{
    param (
        [Parameter(Mandatory = $true)]
        [switch] $InstallMySqlExt,

        [String] $PackageFolder = 'c:\package',

        [Parameter(Mandatory = $true)]
        [String] $DownloadUri,

        [String] $Vc2012RedistDownloadUri = 'http://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x64.exe',

        [String] $DestinationPath = 'C:\php',

        [Parameter(Mandatory = $true)]
        [String] $ConfigurationPath
    )
    
    Import-DscResource -ModuleName xWebAdministration
    Import-DscResource -ModuleName xPsDesiredStateConfiguration 

    # Make sure the IIS Prerequisites for PHP are present
    IisPreReqs_php Iis
    {
        Ensure = "Present"

        # Removed because this dependency does not work in Windows Server 2012 R2 and below
        # This should work in WMF v5 and above
        # DependsOn = "[File]PackagesFolder"
    }

    # Download and install Visual C Redist2012 from chocolatey.org
    Package vcRedist
    {
        Path = $Vc2012RedistDownloadUri
        ProductId = "{CF2BEA3C-26EA-32F8-AA9B-331F7E34BA97}"
        Name = "Microsoft Visual C++ 2012 x64 Minimum Runtime - 11.0.61030"
        Arguments = "/install /passive /norestart"
    }

    $phpZip = Join-Path $PackageFolder "php.zip"

    $phpDownloadUri = New-Object -TypeName System.Uri $DownloadURI
    $archiveDependsOn = @()
    if ($phpDownloadUri.scheme -ieq "http")
    {
        # Make sure the PHP archive is in the package folder
        xRemoteFile phpArchive
        {
            uri             = $DownloadURI
            DestinationPath = $phpZip
        }
        $archiveDependsOn += "[xRemoteFile]phpArchive"
    }
    else
    {
        $phpZip = $DownloadURI
    }

    # Make sure the content of the PHP archive is in the PHP path
    Archive php
    {
        Path         = $phpZip
        Destination  = $DestinationPath
        DependsOn    = $archiveDependsOn
    }

    if ($InstallMySqlExt)
    {               
        # Make sure the MySql extention for PHP is in the main PHP path
        File phpMySqlExt
        {
            SourcePath = "$($DestinationPath)\ext\php_mysql.dll"
            DestinationPath = "$($DestinationPath)\php_mysql.dll"
            Ensure = "Present"
            DependsOn = @("[Archive]PHP")
            MatchSource = $true
        }
    }

    # Make sure the php.ini is in the Php folder
    File PhpIni
    {
        SourcePath = $ConfigurationPath
        DestinationPath = "$($DestinationPath)\php.ini"
        DependsOn = @("[Archive]PHP")
        MatchSource = $true
    }

    # Make sure the php cgi module is registered with IIS
    xIisModule phpHandler
    {
       Name = "phpFastCgi"
       Path = "$($DestinationPath)\php-cgi.exe"
       RequestPath = "*.php"
       Verb = "*"
       Ensure = "Present"
       DependsOn = @("[Package]vcRedist","[File]PhpIni") 

       # Removed because this dependency does not work in Windows Server 2012 R2 and below
       # This should work in WMF v5 and above
       # "[IisPreReqs_php]Iis" 
    }

    # Make sure the php binary folder is in the path
    Environment PathPhp
    {
        Name = "Path"
        Value = ";$($DestinationPath)"
        Ensure = "Present"
        Path = $true
        DependsOn = "[Archive]PHP"
    }
}
