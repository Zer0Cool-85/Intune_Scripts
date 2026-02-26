function Enforce-Reboot(){
    ## Create argument list variable with path information
    $ArgList = "-Process:Explorer.exe " + "$env:ProgramData\MDM_Scripts\EnforceRestart\Deploy-Application.exe " + "$env:ProgramData\MDM_Scripts\EnforceRestart\Reboot.ps1 " + "-DeploymentType Install" 

    Start-Process "$env:ProgramData\MDM_Scripts\EnforceRestart\ServiceUI.exe" -ArgumentList $ArgList -NoNewWindow -RedirectStandardOutput "$env:ProgramData\MDM_Scripts\EnforceRestart\process_output.txt"
}

try{
    ## Check for the existence of the needed files
    $scriptFolder = "$env:ProgramData\MDM_Scripts\EnforceRestart" 
    $fileCount = (Get-ChildItem $scriptFolder -Recurse | Measure-Object).Count
    if($scriptFolder){
        if($fileCount -ne 19){
            Write-Output "Scripts not present on host"
            Exit 1
        }else{
            ## Run the reboot popup using ServiceUI and the defined args above
            Enforce-Reboot
            Write-Output "Running restart popup"
            exit 0
        }
    }else{
        Write-Output "Scripts not present on host"
        Exit 1
    }
}catch{
    Write-Output "Failed, check logs on host"
    exit 1
}

