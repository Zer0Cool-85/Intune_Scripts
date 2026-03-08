try{
# Double checl for existence of the key for OneDrive-Personal
    $oneDriveKey = "HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
    if(Test-Path $oneDriveKey){
        $pinnedValue = Get-ItemPropertyValue $oneDriveKey -Name "System.IsPinnedToNameSpaceTree"
        if($pinnedValue -eq 1){
            Write-Output "Requires change to registry property value"
            $null = Set-ItemProperty -Path $oneDriveKey -Name "System.IsPinnedToNameSpaceTree" -Value "0" -Force
            $pinnedValue = Get-ItemPropertyValue $oneDriveKey -Name "System.IsPinnedToNameSpaceTree"
            if($pinnedValue -eq 0){
                Write-Output "Success!"
                Exit 0
            }else{
                Write-Output "Failed!"
                Exit 1
            }
        }else{
            Write-Output "Registry value is good!"
            Exit 0
        }
    }else{
        Write-Output "Registry key does not exist"
        Exit 0
    }
}catch{
    Write-Output "ERROR..."
    Exit 1
}
