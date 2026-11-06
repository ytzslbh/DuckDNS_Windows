# DuckDNS Windows 动态域名更新程序
# 适用于 Windows PowerShell 5.1 / Windows 10、11、Windows Server
# 首次运行时输入 DuckDNS 子域名前缀和 Token，自动保存到配置文件。
# 之后每次运行（包括开机自启）自动读取配置，无需手动输入。
# 程序运行期间每 5 分钟检查并更新一次。

$ErrorActionPreference = "Stop"
$LogFile   = Join-Path $PSScriptRoot "duckdns.log"
$ConfigFile = Join-Path $PSScriptRoot "duckdns-config.ini"

function Write-Log {
    param([string]$Message, [string]$Color = "Gray")
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line -ForegroundColor $Color
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

# ---- 读取或创建配置 ----
$needInput = $true
$domain = ""
$token  = ""

if (Test-Path $ConfigFile) {
    try {
        $cfg = Get-Content -LiteralPath $ConfigFile -Encoding UTF8
        $domain = ($cfg | Where-Object { $_ -match '^domain\s*=' }) -replace '^domain\s*=\s*', '' | Select-Object -First 1
        $token  = ($cfg | Where-Object { $_ -match '^token\s*=' })  -replace '^token\s*=\s*', ''  | Select-Object -First 1
        if ($domain) { $domain = $domain.Trim() }
        if ($token)  { $token  = $token.Trim() }
        if ($domain -and $token) {
            $needInput = $false
        }
    } catch {
        # 配置文件读取失败，走手动输入流程
    }
}

# ---- 如果是交互式运行且需要输入 ----
if ($needInput) {
    # 判断是否有交互式终端（计划任务后台运行时没有）
    if ($Host.Name -eq "ConsoleHost" -and [Environment]::UserInteractive) {
        Clear-Host
        Write-Host "==============================================="
        Write-Host "          DuckDNS 动态域名更新程序"
        Write-Host "        首次配置 - 请输入以下信息"
        Write-Host "==============================================="
        Write-Host ""

        $domain = Read-Host "请输入 DuckDNS 子域名前缀（例如 myhome，不要输入 .duckdns.org）"
        $domain = $domain.Trim().ToLowerInvariant()

        if ($domain -notmatch '^[a-z0-9-]+$' -or $domain.Length -gt 63 -or
            $domain.StartsWith("-") -or $domain.EndsWith("-")) {
            Write-Host "域名前缀格式不正确，请检查后重新运行。" -ForegroundColor Red
            Read-Host "按回车退出"
            exit 1
        }

        $secureToken = Read-Host "请输入 DuckDNS Token（输入时不会显示字符）" -AsSecureString
        $tokenPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
        try {
            $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPtr).Trim()
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPtr)
        }

        if ([string]::IsNullOrWhiteSpace($token)) {
            Write-Host "Token 不能为空。" -ForegroundColor Red
            Read-Host "按回车退出"
            exit 1
        }

        # 保存配置文件
        $configContent = @"
domain=$domain
token=$token
"@
        Set-Content -LiteralPath $ConfigFile -Value $configContent -Encoding UTF8 -Force
        Write-Host ""
        Write-Host "配置已保存到：$ConfigFile" -ForegroundColor Cyan
        Write-Host "下次运行（包括开机自启）将自动读取，无需再次输入。" -ForegroundColor Cyan
        Write-Host ""
    } else {
        # 非交互式环境且无配置文件，无法继续
        Write-Log "错误：未找到配置文件且当前为非交互式环境，无法输入信息。请先双击 runDuckDNS.bat 手动运行一次。" "Red"
        exit 1
    }
}

# ---- 兼容 TLS ----
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$domainUrl = [uri]::EscapeDataString($domain)
$tokenUrl  = [uri]::EscapeDataString($token)
$updateUrl = "https://www.duckdns.org/update?domains=$domainUrl&token=$tokenUrl&ip="

# ---- 启动等待：开机后网络可能还没就绪，后台运行时等 30 秒 ----
$isInteractive = ($Host.Name -eq "ConsoleHost") -and [Environment]::UserInteractive
if (-not $isInteractive) {
    Start-Sleep -Seconds 30
}

Write-Host ""
Write-Host "域名：$domain.duckdns.org"
Write-Host "检查间隔：5 分钟"
Write-Host "按 Ctrl+C 可以停止程序。"
Write-Host ""

$lastResult = ""
while ($true) {
    try {
        $rawResponse = (Invoke-WebRequest -Uri $updateUrl -UseBasicParsing -TimeoutSec 20).Content
        if ($rawResponse -is [byte[]]) {
            $response = [System.Text.Encoding]::UTF8.GetString($rawResponse).Trim()
        } elseif ($rawResponse -is [string]) {
            $response = $rawResponse.Trim()
        } else {
            $response = "$rawResponse".Trim()
        }

        if ($response -eq "OK") {
            if ($lastResult -ne "OK") {
                Write-Log "更新成功：$domain.duckdns.org 已请求更新到当前出口公网 IP。" "Green"
            } else {
                Write-Log "检查完成：DuckDNS 返回 OK。" "Green"
            }
            $lastResult = "OK"
        }
        elseif ($response -eq "KO") {
            Write-Log "更新失败：DuckDNS 返回 KO。请核对域名前缀和 Token。" "Red"
            $lastResult = "KO"
        }
        else {
            Write-Log "收到未知响应：$response" "Yellow"
            $lastResult = "OTHER"
        }
    }
    catch {
        Write-Log "请求失败：$($_.Exception.Message)" "Red"
        $lastResult = "ERROR"
    }

    Start-Sleep -Seconds 300
}
