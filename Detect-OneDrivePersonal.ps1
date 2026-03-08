try{
    # Look for existence of the key for OneDrive-Personal
    $oneDriveKey = "HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
    if(Test-Path $oneDriveKey){
        $pinnedValue = Get-ItemPropertyValue $oneDriveKey -Name "System.IsPinnedToNameSpaceTree"
        if($pinnedValue -eq 1){
            Write-Output "Requires change to registry property value"
            Exit 1
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
