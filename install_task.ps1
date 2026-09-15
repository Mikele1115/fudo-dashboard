# Registra la tarea programada de Windows que ejecuta el informe diario todos los días a las 00:00.
# La app corre dentro de WSL (Ubuntu), donde está instalado Ruby con rbenv.
#
# Ejecutar en PowerShell:  .\install_task.ps1
# Para quitarla:           Unregister-ScheduledTask -TaskName "Fudo Informe Diario" -Confirm:$false
# Probar ahora:            Start-ScheduledTask -TaskName "Fudo Informe Diario"

$ErrorActionPreference = 'Stop'

$distro     = 'Ubuntu'
$wslUser    = 'michele'
$projectDir = '~/fudo-dashboard'   # ruta dentro de WSL

$bashCmd = "export PATH=`$HOME/.rbenv/shims:`$PATH; cd $projectDir && bin/rails report:daily >> log/report_task.log 2>&1"

$action   = New-ScheduledTaskAction -Execute 'wsl.exe' -Argument "-d $distro -u $wslUser -e bash -lc `"$bashCmd`""
$trigger  = New-ScheduledTaskTrigger -Daily -At '00:00'
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun `
  -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName 'Fudo Informe Diario' `
  -Description 'Sincroniza ventas de Fudo y envía el informe diario por correo (vía WSL)' `
  -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null

Write-Host "Tarea 'Fudo Informe Diario' registrada: todos los días a las 00:00."
Write-Host "Requisito: el PC debe estar encendido (puede estar bloqueado) con tu sesión iniciada."
Write-Host "Ver registro:  wsl -d $distro -e cat /home/$wslUser/fudo-dashboard/log/report_task.log"
