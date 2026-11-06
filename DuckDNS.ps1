# DuckDNS Windows 动态域名更新程序
# 适用于 Windows PowerShell 5.1 / Windows 10、11、Windows Server
# 首次运行时输入 DuckDNS 子域名前缀和 Token。
# 程序运行期间每 5 分钟检查并更新一次；关闭窗口即停止。

$ErrorActionPreference = "Stop"
$LogFile = Join-Path $PSScriptRoot "duckdns.log"

function Write-Log {
    param([string]$Message, [string]$Color = "Gray")
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line -ForegroundColor $Color
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

Clear-Host
Write-Host "==============================================="
Write-Host "          DuckDNS 动态域名更新程序"
Write-Host "==============================================="
Write-Host ""

$domain = Read-Host "请输入 DuckDNS 子域名前缀（例如 myhome，不要输入 .duckdns.org）"
$domain = $domain.Trim().ToLowerInvariant()

# DuckDNS 子域名前缀通常由字母、数字和连字符组成
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

# 兼容部分旧版 Windows / PowerShell 的 TLS 默认设置
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$domainUrl = [uri]::EscapeDataString($domain)
$tokenUrl = [uri]::EscapeDataString($token)
$updateUrl = "https://www.duckdns.org/update?domains=$domainUrl&token=$tokenUrl&ip="

Write-Host ""
Write-Host "域名：$domain.duckdns.org"
Write-Host "检查间隔：5 分钟"
Write-Host "Token 只保存在本次运行内存中，不写入配置文件。"
Write-Host "按 Ctrl+C 可以停止程序。"
Write-Host ""

$lastResult = ""
while ($true) {
    try {
        $rawResponse = (Invoke-WebRequest -Uri $updateUrl -UseBasicParsing -TimeoutSec 20).Content
        if ($rawResponse -is [byte[]]) {
            $response = [System.Text.Encoding]::UTF8.GetString($rawResponse).Trim()
        } else {
            $response = $rawResponse.Trim()
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
