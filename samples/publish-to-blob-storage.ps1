﻿[cmdletbinding(SupportsShouldProcess=$true)]
param($PublishProperties, $OutputPath)

function Ensure-PublishModuleLoaded{
    [cmdletbinding()]
    param($versionToInstall = '0.0.6-beta',
        $installScriptUrl = 'https://raw.githubusercontent.com/sayedihashimi/publish-module/master/GetPublishModule.ps1',
        $toolsDir = ("$env:LOCALAPPDATA\LigerShark\tools\"),
        $installScriptPath = (Join-Path $toolsDir 'GetPublishModule.ps1'))
    process{
        if(!(Test-Path $installScriptPath)){
            $installDir = [System.IO.Path]::GetDirectoryName($installScriptPath)
            if(!(Test-Path $installDir)){
                New-Item -Path $installDir -ItemType Directory -WhatIf:$false | Out-Null
            }

            'Downloading from [{0}] to [{1}]' -f $installScriptUrl, $installScriptPath| Write-Verbose
            (new-object Net.WebClient).DownloadFile($installScriptUrl,$installScriptPath) | Out-Null       
        }
	
		$installScriptArgs = @($versionToInstall,$toolsDir)
        # seems to be the best way to invoke a .ps1 file with parameters
        Invoke-Expression "& `"$installScriptPath`" $installScriptArgs"
    }
}

function Publish-FolderToBlobStorage{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateScript({Test-Path $_ -PathType Container})] 
        $folder,
        [Parameter(Mandatory=$true,Position=1)]
        $storageAcctName,
        [Parameter(Mandatory=$true,Position=2)]
        $storageAcctKey,
        [Parameter(Mandatory=$true,Position=3)]
        $containerName
    )
    begin{
        'Publishing folder to blob storage. [folder={0},storageAcctName={1},storageContainer={2}]' -f $folder,$storageAcctName,$containerName | Write-Output
        Push-Location
        Set-Location $folder
        $destContext = New-AzureStorageContext -StorageAccountName $storageAcctName -StorageAccountKey $storageAcctKey
    }
    end{ Pop-Location }
    process{
        $allFiles = (Get-ChildItem $folder -Recurse -File).FullName

        foreach($file in $allFiles){
            $relPath = (Resolve-Path $file -Relative).TrimStart('.\')
            "relPath: [$relPath]" | Write-Output

            Set-AzureStorageBlobContent -Blob $relPath -File $file -Container $containerName -Context $destContext
        }
    }
}
$whatifpassed = !($PSCmdlet.ShouldProcess($env:COMPUTERNAME,"publish"))
'loading publish-module' | Write-Output
Ensure-PublishModuleLoaded

'Registering blob storage handler' | Write-Verbose
Register-AspnetPublishHandler -name 'BlobStorage' -handler {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        $PublishProperties,
        [Parameter(Mandatory = $true,Position=1,ValueFromPipelineByPropertyName=$true)]
        $OutputPath
    )
    
    '[op={0},san={1},con={2}' -f $OutputPath,$PublishProperties['StorageAcctName'],$PublishProperties['StorageContainer'] | Write-Output

    Publish-FolderToBlobStorage -folder $OutputPath -storageAcctName $PublishProperties['StorageAcctName'] -storageAcctKey $PublishProperties['StorageAcctKey'] -containerName $PublishProperties['StorageContainer']
}

'Calling AspNet-Publish' | Write-Output
# call AspNet-Publish to perform the publish operation
AspNet-Publish -publishProperties $PublishProperties -OutputPath $OutputPath -Verbose -WhatIf:$whatifpassed
