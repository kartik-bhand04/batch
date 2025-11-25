@echo off
title PREP NEW MACHINE V2 - FIXED (DOMAIN + WORKGROUP + PSEXEC 1385 FIX)

:: =============================================================================
:: LOG FILE
:: =============================================================================
set "LOGFILE=%~dp0PrepNewMachine_log.txt"

echo =============================================================== > "%LOGFILE%"
echo START: %DATE% %TIME% >> "%LOGFILE%"
echo MACHINE: %COMPUTERNAME% >> "%LOGFILE%"
echo USER: %USERNAME% >> "%LOGFILE%"
echo MODE: UNIVERSAL DOMAIN + WORKGROUP + FULL RIGHTS >> "%LOGFILE%"
echo SCRIPT: PrepNewMachineV2_Fixed.bat >> "%LOGFILE%"
echo =============================================================== >> "%LOGFILE%"

set ERRORCOUNT=0

echo ============================================================
echo PREPARING MACHINE FOR REMOTE INSTALL (UPDATED + FIXED)
echo ============================================================
echo Log: %LOGFILE%
echo.


:: =============================================================================
:: CHECK ADMIN PRIVILEGES
:: =============================================================================
echo Checking Administrator Rights...
net session >nul 2>&1
if errorlevel 1 (
    echo FAIL: Run as Administrator >> "%LOGFILE%"
    echo ERROR: Run script as Administrator!
    pause
    exit /b
)
echo OK >> "%LOGFILE%"
echo OK


:: =============================================================================
:: STEP 1 - DISABLE TOKEN FILTER (REQUIRED FOR C$)
:: =============================================================================
echo Enabling UAC LocalAccountTokenFilterPolicy...
reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System ^
/v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f >> "%LOGFILE%" 2>&1
if errorlevel 1 ( set /a ERRORCOUNT+=1 ) else ( echo OK )


:: =============================================================================
:: STEP 2 - FORCE ADMIN SHARES (DOMAIN + WORKGROUP)
:: =============================================================================
echo Forcing C$ and Admin Shares...

reg add HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters ^
/v AutoShareWks /t REG_DWORD /d 1 /f >> "%LOGFILE%" 2>&1

reg add HKLM\SYSTEM\CurrentControlSet\Control\Lsa ^
/v restrictanonymous /t REG_DWORD /d 0 /f >> "%LOGFILE%" 2>&1

reg add HKLM\SYSTEM\CurrentControlSet\Control\Lsa ^
/v forceguest /t REG_DWORD /d 0 /f >> "%LOGFILE%" 2>&1

dism /online /enable-feature /featurename:SMB1Protocol /all /norestart >> "%LOGFILE%" 2>&1

:: Confirm C$
net share | findstr /I "C$" >nul
if errorlevel 1 (
    echo FAIL - C$ not available (will retry after rights) >> "%LOGFILE%"
    set /a ERRORCOUNT+=1
) else (
    echo OK
)


:: =============================================================================
:: STEP 3 - FIREWALL RULES
:: =============================================================================
echo Configuring Firewall Rules...

netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes >> "%LOGFILE%"
netsh advfirewall firewall set rule group="Remote Service Management" new enable=Yes >> "%LOGFILE%"
netsh advfirewall firewall add rule name="AllowICMPv4" protocol=icmpv4 dir=in action=allow >> "%LOGFILE%"
netsh advfirewall firewall add rule name="SMB137" dir=in protocol=udp localport=137 action=allow >> "%LOGFILE%"
netsh advfirewall firewall add rule name="SMB138" dir=in protocol=udp localport=138 action=allow >> "%LOGFILE%"
netsh advfirewall firewall add rule name="SMB139" dir=in protocol=tcp localport=139 action=allow >> "%LOGFILE%"
netsh advfirewall firewall add rule name="SMB445" dir=in protocol=tcp localport=445 action=allow >> "%LOGFILE%"

if errorlevel 1 ( set /a ERRORCOUNT+=1 ) else ( echo OK )


:: =============================================================================
:: STEP 4 - RemoteRegistry + WinRM
:: =============================================================================
echo Enabling RemoteRegistry and WinRM...

sc config RemoteRegistry start=auto >> "%LOGFILE%"
net start RemoteRegistry >> "%LOGFILE%"

sc config winrm start=auto >> "%LOGFILE%"
net start winrm >> "%LOGFILE%"

sc query RemoteRegistry | find "RUNNING" >nul
if errorlevel 1 ( set /a ERRORCOUNT+=1 ) else ( echo OK )


:: =============================================================================
:: STEP 5 - Restart SMB
:: =============================================================================
echo Restarting LanmanServer...
net stop server /y >> "%LOGFILE%"
net start server >> "%LOGFILE%"

sc query server | find "RUNNING" >nul
if errorlevel 1 ( set /a ERRORCOUNT+=1 ) else ( echo OK )


:: =============================================================================
:: STEP 6 - UNC C$ TEST
:: =============================================================================
echo Testing local C$...
mkdir \\%COMPUTERNAME%\C$\PrepTest_%RANDOM% >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo FAIL - C$ still blocked >> "%LOGFILE%"
    set /a ERRORCOUNT+=1
) else (
    echo OK
)


:: =============================================================================
:: STEP 7 - FIX PsExec ERROR 1385 (GRANT ALL RIGHTS)
:: =============================================================================
echo Applying PsExec Logon Rights (FULL FIX)...

echo [Unicode] > %temp%\rights.inf
echo Unicode=yes >> %temp%\rights.inf
echo [Version] >> %temp%\rights.inf
echo signature="$CHICAGO$" >> %temp%\rights.inf
echo Revision=1 >> %temp%\rights.inf
echo [Privilege Rights] >> %temp%\rights.inf

:: SID for BUILTIN\Administrators
echo SeRemoteInteractiveLogonRight=*S-1-5-32-544 >> %temp%\rights.inf
echo SeNetworkLogonRight=*S-1-5-32-544 >> %temp%\rights.inf
echo SeInteractiveLogonRight=*S-1-5-32-544 >> %temp%\rights.inf
echo SeBatchLogonRight=*S-1-5-32-544 >> %temp%\rights.inf

secedit /configure /db %temp%\rights.db /cfg %temp%\rights.inf /areas USER_RIGHTS >> "%LOGFILE%"

if errorlevel 1 (
    echo FAIL - User rights apply failed >> "%LOGFILE%"
    set /a ERRORCOUNT+=1
) else (
    echo OK
)


:: =============================================================================
:: FINAL SUMMARY
:: =============================================================================
echo.
echo ===================== SUMMARY ==========================
echo HOSTNAME:
hostname

echo.
echo WHOAMI:
whoami

echo.
echo ERRORS FOUND: %ERRORCOUNT%
echo Log saved at: %LOGFILE%
echo =========================================================

start "" "%LOGFILE%"
pause
exit /b
