# Ruta del archivo de salida
$output_file = "$env:USERPROFILE\Desktop\informe_seguridad.txt"

# Función para agregar datos con encabezado y descripción clara
function Append-Output {
    param (
        [string]$title,
        [pscustomobject[]]$data = $null,
        [string]$description
    )

    # Escribir encabezado y descripción
    "`n=== $title ===`n" | Add-Content $output_file
    "$description`n" | Add-Content $output_file

    # Escribir datos si están disponibles
    if ($data) {
        foreach ($item in $data) {
            $item.PSObject.Properties | ForEach-Object { 
                "$($_.Name): $($_.Value)" | Add-Content $output_file 
            }
            "`n" | Add-Content $output_file
        }
    } else {
        "No se encontraron datos para $title`n" | Add-Content $output_file
    }
}

# Limpiar archivo previo
Remove-Item $output_file -ErrorAction Ignore

# Cabecera inicial del informe
"=== Informe de Seguridad del Sistema ===`n" | Add-Content $output_file
"Generado el: $(Get-Date)" | Add-Content $output_file
"----------------------------------------`n" | Add-Content $output_file

# Información del sistema operativo
try {
    $os_version = Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version
    Append-Output "Sistema Operativo" ([pscustomobject]@{Name = "SO"; Value = "$($os_version.Caption) $($os_version.Version)"}, 
        "Este es el sistema operativo que tienes instalado en tu equipo, como Windows 10 o Windows 11, junto con su versión.")
} catch {
    Append-Output "Error de Sistema Operativo" $null "No se pudo obtener la información del sistema operativo. Verifica los permisos o la conectividad."
}

# Software instalado
try {
    $softwareList = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" |
    Select-Object DisplayName, DisplayVersion | Where-Object { $_.DisplayName -and $_.DisplayVersion } | 
    Sort-Object DisplayName -Unique
    Append-Output "Software Instalado" $softwareList "Lista del software actualmente instalado en tu equipo. Revisa los programas para identificar software sospechoso o innecesario."
} catch {
    Append-Output "Error de Software Instalado" $null "No se pudo obtener la lista de software instalado. Verifica si tienes permisos suficientes."
}

# Especificaciones del hardware
try {
    $cpu_info = Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores
    $ram_info = Get-CimInstance Win32_ComputerSystem | Select-Object @{Name="RAM (GB)"; Expression={"{0:N2}" -f ($_.TotalPhysicalMemory / 1GB)}}
    Append-Output "Procesador" ([pscustomobject]@{Name = "Modelo"; Value = $cpu_info.Name; Núcleos = "$($cpu_info.NumberOfCores)"}, 
        "Especificaciones del procesador de tu equipo, que afectan su rendimiento general.")
    Append-Output "Memoria RAM" ([pscustomobject]@{Name = "RAM"; Value = "$($ram_info.'RAM (GB)') GB"}, 
        "Cantidad de memoria RAM instalada, que influye en el rendimiento multitarea.")
} catch {
    Append-Output "Error de Hardware" $null "No se pudo obtener la información de hardware. Verifica los permisos del sistema."
}

# Actualizaciones instaladas
try {
    $hotfixes = Get-HotFix | Select-Object Description, HotFixID, InstalledOn
    Append-Output "Actualizaciones Instaladas" $hotfixes "Lista de actualizaciones críticas aplicadas en el sistema para corregir vulnerabilidades de seguridad."
} catch {
    Append-Output "Error de Actualizaciones" $null "No se pudo obtener la lista de actualizaciones instaladas. Esto podría afectar la seguridad."
}

# Verificación de actualizaciones automáticas
try {
    $wuauserv_status = (Get-Service -Name "wuauserv").Status
    $wu_auto_updates = if ($wuauserv_status -eq 'Running') { "Habilitadas" } else { "Deshabilitadas" }
    Append-Output "Actualizaciones Automáticas" ([pscustomobject]@{ Name = "Estado"; Value = $wu_auto_updates }, 
        "El estado de las actualizaciones automáticas. Tenerlas habilitadas garantiza que tu equipo reciba las últimas mejoras de seguridad.")
} catch {
    Append-Output "Error de Actualizaciones Automáticas" $null "No se pudo verificar el estado de las actualizaciones automáticas. Esto podría comprometer la seguridad."
}

# Estado del firewall
try {
    Get-NetFirewallProfile | ForEach-Object {
        Append-Output "Estado del Firewall" ([pscustomobject]@{ Name = $_.Name; Estado = if ($_.Enabled) { "Habilitado" } else { "Deshabilitado" } }, 
            "El firewall ayuda a proteger tu equipo de accesos no autorizados. Asegúrate de que esté habilitado en todos los perfiles.")
    }
    $firewall_rules = Get-NetFirewallRule | Where-Object { $_.Enabled -eq 'True' } | Select-Object Name, Direction, Action
    Append-Output "Reglas activas del Firewall" $firewall_rules "Lista de reglas del firewall que están activas. Revisa las reglas no familiares o innecesarias."
} catch {
    Append-Output "Error del Firewall" $null "No se pudo verificar el estado del firewall. Esto podría dejar tu equipo vulnerable."
}

# Estado del antivirus
try {
    $antivirus_status = Get-MpComputerStatus | Select-Object AMServiceEnabled, RealTimeProtectionEnabled
    Append-Output "Antivirus" ([pscustomobject]@{ Nombre = "Estado Antivirus"; Value = if ($antivirus_status.AMServiceEnabled) { "Habilitado" } else { "Deshabilitado" } }, 
        "El antivirus ayuda a proteger tu sistema de malware. Verifica que esté habilitado.")
    $tamper_protection = Get-MpPreference | Select-Object -ExpandProperty DisableRealtimeMonitoring
    Append-Output "Protección contra alteraciones" ([pscustomobject]@{ Name = "Estado"; Value = if ($tamper_protection -eq $false) { "Habilitada" } else { "Deshabilitada" } }, 
        "La protección contra alteraciones evita que el antivirus sea deshabilitado por aplicaciones maliciosas.")
} catch {
    Append-Output "Error del Antivirus" $null "No se pudo verificar el estado del antivirus o la protección contra alteraciones. Verifica la configuración."
}

# Puertos abiertos (comunes)
try {
    $common_ports = @(80, 443, 3389, 445) # HTTP, HTTPS, RDP, SMB
    $open_ports = foreach ($port in $common_ports) {
        $result = Test-NetConnection -ComputerName localhost -Port $port
        [pscustomobject]@{Puerto = $port; Estado = if ($result.TcpTestSucceeded) { "Abierto" } else { "Cerrado" }}
    }
    Append-Output "Puertos Abiertos" $open_ports "Lista de puertos de red abiertos en tu equipo. Revisa si algún puerto innecesario está abierto."
} catch {
    Append-Output "Error en Puertos Abiertos" $null "No se pudo verificar el estado de los puertos abiertos. Revisa la configuración de red."
}

# Cuentas de usuario sin contraseña
try {
    $user_accounts = Get-WmiObject -Class Win32_UserAccount | Where-Object { $_.PasswordRequired -eq $false }
    Append-Output "Usuarios sin contraseña" $user_accounts "Lista de cuentas sin contraseña configurada. Tener cuentas sin contraseña expone el equipo a riesgos."
} catch {
    Append-Output "Error de Usuarios sin Contraseña" $null "No se pudo obtener la lista de cuentas de usuario. Verifica los permisos."
}

# Verificación de SMBv1
try {
    $smb1_status = Get-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" | Select-Object -ExpandProperty State
    $smb_status = [pscustomobject]@{ Protocolo = "SMBv1"; Estado = if ($smb1_status -eq 'Enabled') { "Habilitado" } else { "Deshabilitado" } }
    Append-Output "Protocolo SMBv1" $smb_status "SMBv1 es un protocolo obsoleto y no seguro. Se recomienda deshabilitarlo si está habilitado."
} catch {
    Append-Output "Error en Verificación de SMBv1" $null "No se pudo verificar el estado de SMBv1."
}

# Confirmación de que el informe ha sido generado
Write-Host "Informe de seguridad generado en: $output_file" -ForegroundColor Green