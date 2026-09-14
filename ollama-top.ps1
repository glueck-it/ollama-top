<#
.SYNOPSIS
    Universal AI, Database, GPU & Batch Job Dashboard for Windows PowerShell.
.DESCRIPTION
    Zero-Dependency Open-Source Live Monitor for:
    - Batch Jobs & Progress Bars (piped log stream, item count, speed, ETA)
    - Hardware Sensors (NVIDIA GPU, Host CPU/RAM, Intel NPU & iGPU)
    - Network Traffic (live In/Out bandwidth, session data volume)
    - Universal Database & Service Endpoints (PostgreSQL, MySQL, Oracle, DB2, Informix, SAP HANA, SQL Server, Redis, Mongo, ClickHouse, etc.)
    - AI / LLM Inference Runtimes (Ollama multi-instance live token speeds, context, VRAM)
    - Active Parallel Client Workers (Perl, Python, PHP, Node, Java, etc.)
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline = $true)]
    [psobject]$InputObject,

    [int]$Total = 0,
    [string]$Title = "Batch Job",
    [int]$RefreshMs = 1200,
    [int[]]$WatchPorts = @(),
    [int[]]$OllamaPorts = @(11434, 11435, 8000),
    [int]$Width = 0
)

begin {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    $Host.UI.RawUI.WindowTitle = "Universal Live Monitor | $Title"
    
    # Solid block & seamless box drawing characters
    $script:chFull   = [string][char]0x2588 # █ (Progress bar fill)
    $script:chLight  = [string][char]0x2591 # ░ (Progress bar empty)
    $script:chHBar   = [string][char]0x2500 # ─ (Box drawings light horizontal - gapless!)
    $script:chDBar   = [string][char]0x2550 # ═ (Box drawings double horizontal - gapless!)
    $script:chThick  = [string][char]0x2501 # ━ (Box drawings heavy horizontal)

    # State tracking
    $startTime = [System.Diagnostics.Stopwatch]::StartNew()
    $lastHwPoll = [System.Diagnostics.Stopwatch]::StartNew()
    $currentCount = 0
    $totalCount = $Total
    $recentLines = [System.Collections.Generic.Queue[string]]::new()
    $maxRecentLines = 4

    # Comprehensive Service & Database Catalog
    $script:knownServices = @{
        # Relational & Enterprise Databases
        1521  = "Oracle DB (Listener)"
        1522  = "Oracle DB"
        1526  = "IBM Informix / Oracle"
        1527  = "IBM Informix / Oracle"
        2483  = "Oracle DB (SSL/TCPS)"
        2484  = "Oracle DB (SSL/TCPS)"
        1433  = "Microsoft SQL Server"
        1434  = "MS SQL Monitor/Browser"
        50000 = "IBM DB2 (Instance)"
        50001 = "IBM DB2 (SSL)"
        60000 = "IBM DB2 (Communications)"
        9088  = "IBM Informix (Online)"
        9089  = "IBM Informix (SSL)"
        30013 = "SAP HANA (Instance 00)"
        30015 = "SAP HANA (SQL/MDX 00)"
        30213 = "SAP HANA (Instance 02)"
        30215 = "SAP HANA (SQL/MDX 02)"
        39013 = "SAP HANA (System DB 90)"
        39015 = "SAP HANA (SQL/MDX 90)"
        39017 = "SAP HANA (Tenant 90)"
        5432  = "PostgreSQL (Default)"
        5433  = "PostgreSQL"
        5434  = "PostgreSQL"
        5435  = "PostgreSQL"
        5436  = "PostgreSQL"
        5437  = "PostgreSQL"
        5438  = "PostgreSQL"
        5439  = "PostgreSQL"
        6432  = "PgBouncer (Postgres Pool)"
        3306  = "MySQL / MariaDB"
        3307  = "MySQL / MariaDB"
        33060 = "MySQL (X-Protocol)"
        5000  = "Sybase / SAP ASE"
        4100  = "Sybase / SAP ASE"
        1025  = "Teradata DBS"

        # NoSQL, Caches & Search
        27017 = "MongoDB"
        27018 = "MongoDB (Shard)"
        27019 = "MongoDB (Config)"
        6379  = "Redis / Valkey Cache"
        6380  = "Redis (TLS/Cluster)"
        26379 = "Redis Sentinel"
        9042  = "Apache Cassandra (CQL)"
        9160  = "Apache Cassandra (Thrift)"
        8123  = "ClickHouse (HTTP API)"
        9000  = "ClickHouse (Native/TCP)"
        9200  = "Elasticsearch / OpenSearch"
        9300  = "Elasticsearch (Cluster)"
        7474  = "Neo4j (HTTP)"
        7687  = "Neo4j (Bolt)"
        5984  = "Apache CouchDB"
        8086  = "InfluxDB (TSDB)"
        11211 = "Memcached"

        # Message Queues & Event Streaming
        9092  = "Apache Kafka"
        9093  = "Apache Kafka (SSL)"
        5672  = "RabbitMQ (AMQP)"
        15672 = "RabbitMQ (Management)"

        # AI, LLM Inference & App Servers
        11434 = "Ollama (NVIDIA/Primary)"
        11435 = "Ollama (iGPU/Secondary)"
        8000  = "HTTP API / vLLM"
        8080  = "HTTP / TGI / AppServer"
        1234  = "LM Studio API"
        5001  = "TextGen WebUI"
    }

    function Get-ServiceName([int]$port) {
        if ($script:knownServices.ContainsKey($port)) {
            return $script:knownServices[$port]
        }
        if ($port -match '^3\d{2}(13|15|17)$') { return "SAP HANA (Port $port)" }
        if ($port -ge 5432 -and $port -le 5440) { return "PostgreSQL (Port $port)" }
        if ($port -ge 3306 -and $port -le 3310) { return "MySQL / MariaDB" }
        if ($port -ge 1521 -and $port -le 1530) { return "Oracle DB" }
        if ($port -ge 50000 -and $port -le 50010) { return "IBM DB2" }
        if ($port -ge 9088 -and $port -le 9091) { return "IBM Informix" }
        if ($port -in $OllamaPorts) { return "Ollama / LLM Engine" }
        return "TCP Service"
    }

    function Get-NetworkScope([string]$ip) {
        if ($ip -match '^127\.|^::1$|^localhost$') {
            return "Localhost IPC (Loopback)"
        }
        if ($ip -match '^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.') {
            return "Local LAN / On-Premise"
        }
        return "Remote WAN / Cloud"
    }

    # Locate nvidia-smi
    $script:nvismiPath = $null
    $possibleNvidiaPaths = @(
        "C:\Windows\System32\DriverStore\FileRepository\nvtfi.inf_amd64_884f78085512abd5\nvidia-smi.exe",
        "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe",
        "C:\Windows\System32\nvidia-smi.exe"
    )
    foreach ($p in $possibleNvidiaPaths) {
        if (Test-Path $p) { $script:nvismiPath = $p; break }
    }
    if (-not $script:nvismiPath) {
        $found = Get-ChildItem -Path "C:\Windows\System32\DriverStore\FileRepository" -Filter "nvidia-smi.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName -First 1
        if ($found) { $script:nvismiPath = $found }
    }

    # Locate Ollama server log file
    $script:ollamaLog = $null
    $possibleLogPaths = @(
        "$env:LOCALAPPDATA\Ollama\server.log",
        "$env:USERPROFILE\.ollama\server.log",
        "$env:HOME/.ollama/server.log"
    )
    foreach ($lp in $possibleLogPaths) {
        if (Test-Path $lp) { $script:ollamaLog = $lp; break }
    }

    # CPU Static Specs
    $cpuInfo = Get-CimInstance Win32_Processor -Property Name,NumberOfCores,NumberOfLogicalProcessors -ErrorAction SilentlyContinue | Select-Object -First 1
    $cpuName = if ($cpuInfo) { ($cpuInfo.Name -replace '\(R\)|\(TM\)|\bCPU\b','').Trim() } else { "Host CPU" }
    $cpuCores = if ($cpuInfo) { "$($cpuInfo.NumberOfCores)C/$($cpuInfo.NumberOfLogicalProcessors)T" } else { "" }

    # NPU & Integrated GPU Detection
    $script:npuDevice = Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match 'AI Boost|\bNPU\b|Neural' } | Select-Object -First 1 Name, Status
    $script:intelGpuDevice = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'Intel' } | Select-Object -First 1 Name
    $script:intelLuid = $null
    if ($script:intelGpuDevice) {
        $gsc = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -Filter "Name like '%GSC%'" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($gsc -and $gsc.Name -match 'luid_(0x[0-9a-fA-F]+_0x[0-9a-fA-F]+)') {
            $script:intelLuid = $matches[1]
        }
    }

    # Per-port token speeds cache and history
    $script:cachedPromptSpeedByPort = @{}
    $script:cachedGenSpeedByPort    = @{}
    $script:promptHistoryByPort     = @{}
    $script:genHistoryByPort        = @{}
    $script:seenLogTimingsByPort    = @{}
    $script:resetNoticeUntil        = [DateTime]::MinValue

    # Dynamic Ollama Log Resolution & Slot Configuration
    $script:resolvedLogByPort = @{}
    $script:slotsByPort       = @{}

    foreach ($p in $OllamaPorts) {
        $script:cachedPromptSpeedByPort[$p] = 0.0
        $script:cachedGenSpeedByPort[$p]    = 0.0
        $script:promptHistoryByPort[$p]     = [System.Collections.Generic.List[double]]::new()
        $script:genHistoryByPort[$p]        = [System.Collections.Generic.List[double]]::new()
        $script:seenLogTimingsByPort[$p]    = [System.Collections.Generic.HashSet[string]]::new()
    }

    function Get-LogTailLines([string]$path, [int]$byteCount = 65536) {
        if (-not $path -or -not (Test-Path $path)) { return @() }
        try {
            $fs = [System.IO.FileStream]::new($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $offset = [math]::Max(0L, ($fs.Length - $byteCount))
            $fs.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
            $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
            if ($offset -gt 0) { $sr.ReadLine() | Out-Null }
            $lines = [System.Collections.Generic.List[string]]::new()
            while (-not $sr.EndOfStream) {
                $lines.Add($sr.ReadLine())
            }
            $sr.Close()
            $fs.Close()
            return $lines
        } catch {
            return @()
        }
    }

    function Get-LogHeadLines([string]$path, [int]$lineCount = 40) {
        if (-not $path -or -not (Test-Path $path)) { return @() }
        try {
            $fs = [System.IO.FileStream]::new($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
            $lines = [System.Collections.Generic.List[string]]::new()
            $cnt = 0
            while (-not $sr.EndOfStream -and $cnt -lt $lineCount) {
                $lines.Add($sr.ReadLine())
                $cnt++
            }
            $sr.Close()
            $fs.Close()
            return $lines
        } catch {
            return @()
        }
    }

    function Resolve-OllamaLogPath([int]$port) {
        if ($script:resolvedLogByPort.ContainsKey($port)) {
            $cached = $script:resolvedLogByPort[$port]
            if ($cached -and (Test-Path $cached)) {
                $item = Get-Item $cached -ErrorAction SilentlyContinue
                if ($item -and ($item.LastWriteTime -ge [DateTime]::Now.AddMinutes(-10))) {
                    return $cached
                }
            }
        }

        # 1. Standard candidates
        $candidates = [System.Collections.Generic.List[string]]::new()
        if ($port -eq 11434) {
            $candidates.Add("$env:LOCALAPPDATA\Ollama\server.log")
            $candidates.Add("$env:USERPROFILE\.ollama\server.log")
            $candidates.Add("$env:HOME/.ollama/server.log")
        }
        $candidates.Add("$env:LOCALAPPDATA\Ollama\server-$port.log")
        $candidates.Add("$env:LOCALAPPDATA\Ollama\server_$port.log")
        $candidates.Add("$env:TEMP\ollama-$port.log")
        $candidates.Add("$env:TEMP\ollama_$port.log")

        # 2. Dynamic Discovery in Tasks & Temp Logs (actively modified)
        try {
            $taskLogs = Get-ChildItem -Path "$env:USERPROFILE\.gemini\antigravity\brain\*\.system_generated\tasks\*.log" -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending | Select-Object -First 15
            foreach ($tl in $taskLogs) {
                $headLines = Get-LogHeadLines -path $tl.FullName -lineCount 30
                $head = $headLines -join "`n"
                if ($head -match ("Listening on 127\.0\.0\.1:" + $port) -or $head -match ("OLLAMA_HOST:.*?127\.0\.0\.1:" + $port)) {
                    $candidates.Add($tl.FullName)
                }
            }
        } catch {}

        # Select candidate with the freshest modification time
        $existing = $candidates | Where-Object { Test-Path $_ } | ForEach-Object { Get-Item $_ } | Sort-Object LastWriteTime -Descending
        if ($existing) {
            $freshest = $existing[0].FullName
            $script:resolvedLogByPort[$port] = $freshest
            return $freshest
        }

        return $null
    }

    function Get-OllamaSlots([int]$port, [string]$logPath) {
        if ($script:slotsByPort.ContainsKey($port) -and $script:slotsByPort[$port] -gt 0) {
            return $script:slotsByPort[$port]
        }
        $slots = 1
        if ($logPath -and (Test-Path $logPath)) {
            try {
                $headLines = Get-LogHeadLines -path $logPath -lineCount 40
                $head = $headLines -join "`n"
                if ($head -match '-np\s+(\d+)') {
                    $slots = [int]$matches[1]
                } elseif ($head -match 'OLLAMA_NUM_PARALLEL:(\d+)') {
                    $slots = [int]$matches[1]
                }
            } catch {}
        }
        if ($slots -eq 1 -and $port -eq 11434) {
            $regPar = [Environment]::GetEnvironmentVariable('OLLAMA_NUM_PARALLEL', 'User')
            if ($regPar) { $slots = [int]$regPar }
            elseif ($env:OLLAMA_NUM_PARALLEL) { $slots = [int]$env:OLLAMA_NUM_PARALLEL }
        }
        $script:slotsByPort[$port] = $slots
        return $slots
    }

    # Network tracking state
    $script:lastNetTimestamp  = [System.Diagnostics.Stopwatch]::GetTimestamp()
    $script:lastNetBytesRec   = 0L
    $script:lastNetBytesSent  = 0L
    $script:sessionNetRec     = 0L
    $script:sessionNetSent    = 0L
    $script:firstNetSample    = $true
    $script:activeNicName     = "Network Adapter"

    function Format-Bytes([double]$b) {
        if ($b -ge 1GB) { return "{0:N2} GB" -f ($b / 1GB) }
        if ($b -ge 1MB) { return "{0:N2} MB" -f ($b / 1MB) }
        if ($b -ge 1KB) { return "{0:N1} KB" -f ($b / 1KB) }
        return "{0:N0} B" -f $b
    }

    function Reset-SpeedStats {
        foreach ($p in $script:promptHistoryByPort.Keys) {
            $script:promptHistoryByPort[$p].Clear()
            $script:genHistoryByPort[$p].Clear()
        }
        $script:sessionNetRec    = 0L
        $script:sessionNetSent   = 0L
        $script:resetNoticeUntil = [DateTime]::Now.AddSeconds(2.5)
    }

    function Check-KeyboardInput {
        try {
            while ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if ($k.Key -in @([System.ConsoleKey]::Spacebar, [System.ConsoleKey]::R)) {
                    Reset-SpeedStats
                }
            }
        } catch {}
    }

    function Get-StatsSummary([System.Collections.Generic.List[double]]$list, [int]$decimals = 0) {
        if (-not $list -or $list.Count -eq 0) { return $null }
        $sorted = [System.Collections.Generic.List[double]]::new($list)
        $sorted.Sort()
        $min = $sorted[0]
        $max = $sorted[$sorted.Count - 1]
        $sum = 0.0
        foreach ($v in $list) { $sum += $v }
        $avg = $sum / $list.Count
        $mid = [int]($sorted.Count / 2)
        $median = if ($sorted.Count % 2 -ne 0) { $sorted[$mid] } else { ($sorted[$mid - 1] + $sorted[$mid]) / 2.0 }
        
        $fmt = if ($decimals -gt 0) { "{0:N$decimals}" } else { "{0:N0}" }
        return [PSCustomObject]@{
            Min    = $fmt -f $min
            Max    = $fmt -f $max
            Avg    = $fmt -f $avg
            Median = $fmt -f $median
            Count  = $list.Count
        }
    }

    function Get-LatestTokenSpeeds {
        foreach ($port in $OllamaPorts) {
            $targetLog = Resolve-OllamaLogPath $port
            if ($targetLog) {
                try {
                    $tailLines = Get-LogTailLines -path $targetLog -byteCount 65536
                    foreach ($tl in $tailLines) {
                        if ($tl -match 'prompt.*?(?:eval time|processing).*?([0-9\.]+)\s+(?:tokens per second|t/s)') {
                            $speed = [math]::Round([double]$matches[1], 0)
                            $script:cachedPromptSpeedByPort[$port] = $speed
                            if ($script:seenLogTimingsByPort[$port].Add($tl)) {
                                $script:promptHistoryByPort[$port].Add($speed)
                            }
                        }
                        if ($tl -match '(?<!prompt.*?)eval time.*?([0-9\.]+)\s+tokens per second' -or $tl -match 'slot print_timing:.*?tg\s*=\s*([0-9\.]+)\s*t/s') {
                            $speed = [math]::Round([double]$matches[1], 1)
                            $script:cachedGenSpeedByPort[$port] = $speed
                            if ($script:seenLogTimingsByPort[$port].Add($tl)) {
                                $script:genHistoryByPort[$port].Add($speed)
                            }
                        }
                    }
                } catch {}
            }
        }
    }

    # Sensor Cache
    $hw = [ordered]@{
        GpuFound       = $false
        GpuName        = "N/A"
        GpuUtil        = 0
        MemBusUtil     = 0
        VramUsed       = 0.0
        VramTot        = 0.0
        GpuTemp        = 0
        GpuPower       = 0.0
        GpuCoreClk     = 0
        GpuMemClk      = 0
        CpuUtil        = 0
        CpuClk         = 0
        RamUsedGb      = 0.0
        RamTotGb       = 0.0
        NpuFound       = [bool]$script:npuDevice
        NpuName        = if ($script:npuDevice) { $script:npuDevice.Name } else { "None" }
        NpuUtil        = 0
        NpuStatus      = if ($script:npuDevice) { $script:npuDevice.Status } else { "N/A" }
        IntelGpuFound  = [bool]$script:intelGpuDevice
        IntelGpuName   = if ($script:intelGpuDevice) { $script:intelGpuDevice.Name } else { "None" }
        IntelGpuUtil   = 0
        NetRxSpeed     = 0.0
        NetTxSpeed     = 0.0
        NetSessionRec  = 0L
        NetSessionSent = 0L
        NetNicName     = "None"
        PortStats      = @()
        Instances      = @()
        Clients        = @()
    }

    function Update-Sensors {
        # 1. NVIDIA GPU
        if ($script:nvismiPath) {
            try {
                $smi = & $script:nvismiPath --query-gpu=name,utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw,clocks.current.graphics,clocks.current.memory --format=csv,noheader,nounits 2>$null
                if ($smi) {
                    $p = $smi.Split(",") | ForEach-Object { $_.Trim() }
                    $hw.GpuFound   = $true
                    $hw.GpuName    = $p[0] -replace 'NVIDIA |Laptop GPU',''
                    $hw.GpuUtil    = [int]($p[1])
                    $hw.MemBusUtil = [int]($p[2])
                    $hw.VramUsed   = [math]::Round(([double]$p[3] / 1024), 2)
                    $hw.VramTot    = [math]::Round(([double]$p[4] / 1024), 2)
                    $hw.GpuTemp    = [int]($p[5])
                    $hw.GpuPower   = [math]::Round([double]$p[6], 1)
                    $hw.GpuCoreClk = [int]($p[7])
                    $hw.GpuMemClk  = [int]($p[8])
                }
            } catch {}
        }

        # 2. Host CPU & RAM
        try {
            $procLive = Get-CimInstance Win32_Processor -Property LoadPercentage,CurrentClockSpeed -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($procLive) {
                $hw.CpuUtil = [int]$procLive.LoadPercentage
                $hw.CpuClk  = [int]$procLive.CurrentClockSpeed
            }
            $os = Get-CimInstance Win32_OperatingSystem -Property FreePhysicalMemory,TotalVisibleMemorySize -ErrorAction SilentlyContinue
            if ($os) {
                $hw.RamTotGb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
                $hw.RamUsedGb = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
            }
        } catch {}

        # 3. NPU & Integrated GPU Load
        if ($hw.NpuFound -or $hw.IntelGpuFound) {
            try {
                $engs = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction SilentlyContinue
                if ($hw.NpuFound) {
                    $npuEng = $engs | Where-Object { $_.Name -match 'Neural' }
                    $hw.NpuUtil = if ($npuEng) { [int][math]::Min(100, (($npuEng | Measure-Object -Property UtilizationPercentage -Sum).Sum)) } else { 0 }
                }
                if ($hw.IntelGpuFound -and $script:intelLuid) {
                    $intelEng = $engs | Where-Object { $_.Name -match $script:intelLuid }
                    $hw.IntelGpuUtil = if ($intelEng) { [int][math]::Min(100, (($intelEng | Measure-Object -Property UtilizationPercentage -Sum).Sum)) } else { 0 }
                }
            } catch {}
        }

        # 4. Network Traffic & Adapter Stats
        try {
            $curRec = 0L
            $curSent = 0L
            $activeNics = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object {
                $_.OperationalStatus -eq 'Up' -and
                $_.NetworkInterfaceType -notin @([System.Net.NetworkInformation.NetworkInterfaceType]::Loopback) -and
                $_.Description -notmatch 'Virtual|Hyper-V|Filter|QoS|NPCAP'
            }
            if ($activeNics) {
                $primaryNic = $activeNics | Select-Object -First 1
                $script:activeNicName = ($primaryNic.Description -replace 'Family Controller|Controller|Adapter','').Trim()
                foreach ($nic in $activeNics) {
                    $stats = $nic.GetIPStatistics()
                    $curRec += $stats.BytesReceived
                    $curSent += $stats.BytesSent
                }
            }
            $nowTs = [System.Diagnostics.Stopwatch]::GetTimestamp()
            $dtSec = ($nowTs - $script:lastNetTimestamp) / [System.Diagnostics.Stopwatch]::Frequency
            if ($dtSec -le 0) { $dtSec = 1.0 }

            if ($script:firstNetSample) {
                $hw.NetRxSpeed = 0.0
                $hw.NetTxSpeed = 0.0
                $script:firstNetSample = $false
            } else {
                $dRec = [math]::Max(0L, ($curRec - $script:lastNetBytesRec))
                $dSent = [math]::Max(0L, ($curSent - $script:lastNetBytesSent))
                $hw.NetRxSpeed = $dRec / $dtSec
                $hw.NetTxSpeed = $dSent / $dtSec
                $script:sessionNetRec += $dRec
                $script:sessionNetSent += $dSent
            }
            $script:lastNetBytesRec = $curRec
            $script:lastNetBytesSent = $curSent
            $script:lastNetTimestamp = $nowTs
            $hw.NetSessionRec = $script:sessionNetRec
            $hw.NetSessionSent = $script:sessionNetSent
            $hw.NetNicName = $script:activeNicName
        } catch {}

        # 5. Universal Dynamic Service & Database Discovery
        $allTcp = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue
        $portStats = @()
        $clients = @()

        if ($allTcp) {
            # Build target port set
            $monitoredPorts = [System.Collections.Generic.HashSet[int]]::new()
            foreach ($k in $script:knownServices.Keys) { [void]$monitoredPorts.Add($k) }
            foreach ($p in $WatchPorts) { [void]$monitoredPorts.Add($p) }
            foreach ($p in $OllamaPorts) { [void]$monitoredPorts.Add($p) }

            # Filter active connections touching monitored services
            $matchedConns = $allTcp | Where-Object {
                $monitoredPorts.Contains($_.RemotePort) -or $monitoredPorts.Contains($_.LocalPort)
            }

            # Group by RemotePort for service summary
            $groupedByPort = $matchedConns | Group-Object {
                if ($monitoredPorts.Contains($_.RemotePort)) { $_.RemotePort } else { $_.LocalPort }
            }

            foreach ($grp in $groupedByPort) {
                $pNum = [int]$grp.Name
                $svcName = Get-ServiceName $pNum
                $firstConn = $grp.Group | Select-Object -First 1
                $targetAddr = if ($monitoredPorts.Contains($firstConn.RemotePort)) { $firstConn.RemoteAddress } else { $firstConn.LocalAddress }
                $scope = Get-NetworkScope $targetAddr
                
                # Format friendly endpoint
                $endpointStr = "$targetAddr`:$pNum"
                if ($pNum -eq 11434) { $endpointStr += " (RTX 5070 Ti)" }
                elseif ($pNum -eq 11435) { $endpointStr += " (iGPU Vulkan)" }

                $portStats += [PSCustomObject]@{
                    Port    = $pNum
                    Service = $svcName
                    Target  = $endpointStr
                    Sockets = $grp.Count
                    Scope   = $scope
                }
            }

            # Discover active client processes connected to services
            $clientConns = $matchedConns | Where-Object { $monitoredPorts.Contains($_.RemotePort) }
            if ($clientConns) {
                $groupedClients = $clientConns | Group-Object OwningProcess
                foreach ($g in $groupedClients) {
                    $pidNum = [int]$g.Name
                    $proc = Get-Process -Id $pidNum -ErrorAction SilentlyContinue
                    if ($proc -and $proc.ProcessName -notmatch 'powershell|pwsh|svchost') {
                        $targetNames = [System.Collections.Generic.List[string]]::new()
                        foreach ($conn in $g.Group) {
                            $rPort = [int]$conn.RemotePort
                            $sName = Get-ServiceName $rPort
                            $sShort = ($sName -split '\(')[0].Trim()
                            $targetNames.Add("$sShort ($rPort)")
                        }
                        $targetStr = ($targetNames | Select-Object -Unique) -join ', '
                        $clients += [PSCustomObject]@{
                            PID         = $pidNum
                            Name        = $proc.ProcessName
                            Target      = $targetStr
                            MemMB       = [math]::Round($proc.WorkingSet64 / 1MB, 1)
                            CpuSec      = [math]::Round($proc.CPU, 1)
                            TargetPorts = @($g.Group | ForEach-Object { [int]$_.RemotePort } | Select-Object -Unique)
                        }
                    }
                }
            }
        }
        $hw.PortStats = $portStats | Sort-Object Sockets -Descending
        $hw.Clients   = $clients   | Sort-Object PID

        # 6. Read latest Token Speeds from Ollama server.log
        Get-LatestTokenSpeeds

        # 7. Ollama REST API per Port (if running)
        $instances = @()
        foreach ($port in $OllamaPorts) {
            try {
                $res = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/ps" -TimeoutSec 1 -ErrorAction SilentlyContinue
                $targetLog = Resolve-OllamaLogPath $port
                $slots = Get-OllamaSlots $port $targetLog
                $slotsStr = if ($slots -gt 1) { "$slots slots" } else { "1 slot" }

                if ($res -and $res.models -and $res.models.Count -gt 0) {
                    $pSpeed = if ($script:cachedPromptSpeedByPort.ContainsKey($port)) { $script:cachedPromptSpeedByPort[$port] } else { 0.0 }
                    $gSpeed = if ($script:cachedGenSpeedByPort.ContainsKey($port)) { $script:cachedGenSpeedByPort[$port] } else { 0.0 }
                    $pSpeedStr = if ($pSpeed -gt 0) { "{0:N0} Tok/s" -f $pSpeed } else { "Waiting..." }
                    $gSpeedStr = if ($gSpeed -gt 0) { "{0:N1} Tok/s" -f $gSpeed } else { "Waiting..." }

                    foreach ($m in $res.models) {
                        $vramGb = [math]::Round($m.size_vram / 1GB, 2)
                        $instances += [PSCustomObject]@{
                            Port        = $port
                            Model       = $m.name
                            Slots       = $slotsStr
                            SlotsNum    = $slots
                            Ctx         = "$($m.context_length)"
                            Vram        = "${vramGb} GB"
                            VramBytes   = [int64]$m.size_vram
                            PromptSpeed = $pSpeedStr
                            GenSpeed    = $gSpeedStr
                            Status      = "Active"
                        }
                    }
                } elseif ($res) {
                    $instances += [PSCustomObject]@{
                        Port        = $port
                        Model       = "(Ready / No model)"
                        Slots       = $slotsStr
                        SlotsNum    = $slots
                        Ctx         = "-"
                        Vram        = "0 GB"
                        VramBytes   = 0L
                        PromptSpeed = "-"
                        GenSpeed    = "-"
                        Status      = "Idle"
                    }
                }
            } catch {}
        }
        $hw.Instances = $instances
    }

    function Format-Bar([double]$Pct, [int]$Width = 16) {
        $p = [math]::Min(1.0, [math]::Max(0.0, $Pct))
        $filled = [int][math]::Round($p * $Width)
        $empty = $Width - $filled
        return ($script:chFull * $filled) + (" " * $empty)
    }

    function Format-Duration([TimeSpan]$ts) {
        if ($ts.TotalHours -ge 1) {
            return "{0:D2}h {1:D2}m {2:D2}s" -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds
        } else {
            return "{0:D2}m {1:D2}s" -f $ts.Minutes, $ts.Seconds
        }
    }

    function Render-Dashboard {
        Clear-Host
        $now = Get-Date -Format "HH:mm:ss"
        
        # Terminal width: dynamically fit console window without line wrapping
        $termWidth = try { $Host.UI.RawUI.WindowSize.Width } catch { 108 }
        if ($Width -gt 40) {
            $dashWidth = $Width
        } elseif ($termWidth -gt 40) {
            $dashWidth = $termWidth - 1
        } else {
            $dashWidth = 108
        }
        
        $subSep  = $script:chHBar * $dashWidth
        $mainSep = $script:chDBar * $dashWidth

        # Header
        Write-Host ""
        Write-Host $mainSep -ForegroundColor Cyan
        Write-Host "  OLLAMA-TOP: AI, DATABASE & HARDWARE MONITOR  " -NoNewline -ForegroundColor Yellow
        Write-Host "|  $now  |  Host: $env:COMPUTERNAME" -ForegroundColor Gray
        Write-Host $subSep -ForegroundColor DarkCyan

        # 1. BATCH JOB PROGRESS BAR (Falls gepiped oder -Total angegeben)
        if ($totalCount -gt 0 -or $currentCount -gt 0) {
            $elapsed = $startTime.Elapsed
            $speed = if ($elapsed.TotalSeconds -gt 1 -and $currentCount -gt 0) { $currentCount / $elapsed.TotalSeconds } else { 0 }
            
            Write-Host "  JOB: $Title" -ForegroundColor White
            if ($totalCount -gt 0) {
                $pct = $currentCount / $totalCount
                $barStr = Format-Bar -Pct $pct -Width 32
                $pctText = "{0,5:N1}%" -f ($pct * 100)
                
                $remainingItems = [math]::Max(0, ($totalCount - $currentCount))
                $etaSec = if ($speed -gt 0) { $remainingItems / $speed } else { 0 }
                $etaTs = [TimeSpan]::FromSeconds($etaSec)
                $etaStr = if ($speed -gt 0) { Format-Duration $etaTs } else { "Berechne..." }

                Write-Host "  Progress:    [$barStr] " -NoNewline -ForegroundColor Green
                Write-Host $pctText -ForegroundColor Yellow
                Write-Host ("  Status:      {0} / {1} Items  (Offen: {2})" -f $currentCount, $totalCount, $remainingItems) -ForegroundColor White
                Write-Host ("  Speed:       {0:N2} Items/s (~{1:N0}/min) | Elapsed: {2} | ETA: {3}" -f $speed, ($speed * 60), (Format-Duration $elapsed), $etaStr) -ForegroundColor Yellow
            } else {
                Write-Host ("  Status:      {0} Items | Speed: {1:N2} Items/s | Elapsed: {2}" -f $currentCount, $speed, (Format-Duration $elapsed)) -ForegroundColor White
            }
            Write-Host $subSep -ForegroundColor DarkCyan
        }

        # 2. NVIDIA GPU HARDWARE SENSORS
        if ($hw.GpuFound) {
            $deg = [string][char]0x00B0
            $gpuTempColor = "Green"
            if ($hw.GpuTemp -ge 84) { $gpuTempColor = "Red" }
            elseif ($hw.GpuTemp -ge 74) { $gpuTempColor = "Yellow" }

            Write-Host "  NVIDIA GPU SENSORS ($($hw.GpuName)):" -ForegroundColor White

            # GPU Compute + Temp
            $gpuBar = Format-Bar -Pct ($hw.GpuUtil / 100.0) -Width 18
            Write-Host "  GPU Core Load:   " -NoNewline -ForegroundColor Gray
            Write-Host "[$gpuBar] " -NoNewline -ForegroundColor Cyan
            Write-Host ("{0,3}%" -f $hw.GpuUtil) -ForegroundColor Yellow -NoNewline
            Write-Host "  | Clock: " -NoNewline -ForegroundColor Gray
            Write-Host ("{0,4} MHz" -f $hw.GpuCoreClk) -ForegroundColor White -NoNewline
            Write-Host "  | Temp: " -NoNewline -ForegroundColor Gray
            Write-Host ("{0}${deg} C" -f $hw.GpuTemp) -ForegroundColor $gpuTempColor

            # Memory Bus + Power Draw
            $busBar = Format-Bar -Pct ($hw.MemBusUtil / 100.0) -Width 18
            Write-Host "  GPU Memory Bus:  " -NoNewline -ForegroundColor Gray
            Write-Host "[$busBar] " -NoNewline -ForegroundColor Cyan
            Write-Host ("{0,3}%" -f $hw.MemBusUtil) -ForegroundColor Yellow -NoNewline
            Write-Host "  | Clock: " -NoNewline -ForegroundColor Gray
            Write-Host ("{0,4} MHz" -f $hw.GpuMemClk) -ForegroundColor White -NoNewline
            Write-Host "  | Power: " -NoNewline -ForegroundColor Gray
            Write-Host ("{0,5:N1} W" -f $hw.GpuPower) -ForegroundColor White

            # VRAM
            $vramPct = if ($hw.VramTot -gt 0) { $hw.VramUsed / $hw.VramTot } else { 0 }
            $vramBar = Format-Bar -Pct $vramPct -Width 18
            Write-Host "  VRAM Belegung:   " -NoNewline -ForegroundColor Gray
            Write-Host "[$vramBar] " -NoNewline -ForegroundColor Magenta
            Write-Host ("{0,4:N1} / {1:N1} GB ({2:N0}%)" -f $hw.VramUsed, $hw.VramTot, ($vramPct * 100)) -ForegroundColor White

            Write-Host ""
        }

        # 3. HOST CPU & SYSTEM RAM
        $cpuThermal = Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction SilentlyContinue | Select-Object -First 1
        $cpuTempStr = if ($cpuThermal -and $cpuThermal.Temperature -gt 273) { "$([math]::Round($cpuThermal.Temperature - 273.15, 0))${deg} C" } else { "Aktiv" }

        Write-Host "  HOST CPU & SYSTEM ($cpuName - $cpuCores):" -ForegroundColor White

        # CPU Load + Temp
        $cpuBar = Format-Bar -Pct ($hw.CpuUtil / 100.0) -Width 18
        Write-Host "  CPU Auslastung:  " -NoNewline -ForegroundColor Gray
        Write-Host "[$cpuBar] " -NoNewline -ForegroundColor Green
        Write-Host ("{0,3}%" -f $hw.CpuUtil) -ForegroundColor Yellow -NoNewline
        Write-Host "  | Clock: " -NoNewline -ForegroundColor Gray
        Write-Host ("{0,4} MHz" -f $hw.CpuClk) -ForegroundColor White -NoNewline
        Write-Host "  | Temp: " -NoNewline -ForegroundColor Gray
        Write-Host ("{0}" -f $cpuTempStr) -ForegroundColor Cyan

        # Host RAM
        $ramPct = if ($hw.RamTotGb -gt 0) { $hw.RamUsedGb / $hw.RamTotGb } else { 0 }
        $ramBar = Format-Bar -Pct $ramPct -Width 18
        Write-Host "  System RAM:      " -NoNewline -ForegroundColor Gray
        Write-Host "[$ramBar] " -NoNewline -ForegroundColor Blue
        Write-Host ("{0,4:N1} / {1:N1} GB ({2:N0}%)" -f $hw.RamUsedGb, $hw.RamTotGb, ($ramPct * 100)) -ForegroundColor White

        # 4. INTEL NPU & ACCELERATOR SENSORS (Falls im System vorhanden)
        if ($hw.NpuFound -or $hw.IntelGpuFound) {
            Write-Host ""
            $accelHeader = if ($hw.NpuFound) { "INTEL NPU & iGPU SENSORS ($($hw.NpuName)):" } else { "INTEGRATED GPU SENSORS ($($hw.IntelGpuName)):" }
            Write-Host "  $accelHeader" -ForegroundColor White

            if ($hw.NpuFound) {
                $npuBar = Format-Bar -Pct ($hw.NpuUtil / 100.0) -Width 18
                Write-Host "  NPU Neural Load: " -NoNewline -ForegroundColor Gray
                Write-Host "[$npuBar] " -NoNewline -ForegroundColor Green
                Write-Host ("{0,3}%" -f $hw.NpuUtil) -ForegroundColor Yellow -NoNewline
                Write-Host "  | Engine: " -NoNewline -ForegroundColor Gray
                $npuNote = if ($hw.NpuUtil -gt 0) { "Neural (Hardware Active)" } else { "Neural (Standby / Ollama nutzt iGPU Vulkan)" }
                Write-Host $npuNote -ForegroundColor Cyan
            }

            if ($hw.IntelGpuFound) {
                $igpuBar = Format-Bar -Pct ($hw.IntelGpuUtil / 100.0) -Width 18
                Write-Host "  Intel iGPU Load: " -NoNewline -ForegroundColor Gray
                Write-Host "[$igpuBar] " -NoNewline -ForegroundColor Cyan
                Write-Host ("{0,3}%" -f $hw.IntelGpuUtil) -ForegroundColor Yellow -NoNewline
                Write-Host "  | Device: " -NoNewline -ForegroundColor Gray
                Write-Host ("{0}" -f $hw.IntelGpuName) -ForegroundColor White
            }
        }

        # 5. NETWORK TRAFFIC & ACTIVE SERVICES
        Write-Host ""
        $nicTitle = if ($hw.NetNicName -and $hw.NetNicName -ne "None") { " ($($hw.NetNicName))" } else { "" }
        Write-Host ("  NETWORK TRAFFIC & ADAPTER{0}:" -f $nicTitle) -ForegroundColor White

        $rxStr = "$(Format-Bytes $hw.NetRxSpeed)/s"
        $txStr = "$(Format-Bytes $hw.NetTxSpeed)/s"
        $sessRxStr = Format-Bytes $hw.NetSessionRec
        $sessTxStr = Format-Bytes $hw.NetSessionSent

        Write-Host "  Gesamt Live:     " -NoNewline -ForegroundColor Gray
        Write-Host "[In / Download] " -NoNewline -ForegroundColor Cyan
        Write-Host ("{0,-12}" -f $rxStr) -NoNewline -ForegroundColor White
        Write-Host " [Out / Upload] " -NoNewline -ForegroundColor Yellow
        Write-Host ("{0,-12}" -f $txStr) -NoNewline -ForegroundColor White
        Write-Host " | Session: " -NoNewline -ForegroundColor Gray
        Write-Host ("In {0} / Out {1}" -f $sessRxStr, $sessTxStr) -ForegroundColor DarkCyan

        # ACTIVE SERVICES & ENDPOINTS TABLE
        if ($hw.PortStats -and $hw.PortStats.Count -gt 0) {
            Write-Host ""
            Write-Host "  ACTIVE SERVICES & ENDPOINTS (Database, Cache & AI):" -ForegroundColor White
            Write-Host ("  {0,-8}{1,-24}{2,-32}{3,-14}{4,-28}" -f "PORT", "SERVICE", "ENDPOINT / TARGET", "SOCKETS", "SCOPE / NETWORK") -ForegroundColor Gray
            Write-Host $subSep -ForegroundColor DarkGray
            foreach ($ps in $hw.PortStats) {
                $sockColor = if ($ps.Sockets -gt 0) { "Green" } else { "DarkGray" }
                Write-Host "  " -NoNewline
                Write-Host ("{0,-8}" -f $ps.Port) -NoNewline -ForegroundColor Yellow
                Write-Host ("{0,-24}" -f $ps.Service) -NoNewline -ForegroundColor White
                Write-Host ("{0,-32}" -f $ps.Target) -NoNewline -ForegroundColor Cyan
                Write-Host ("{0,-14}" -f "$($ps.Sockets) aktiv") -NoNewline -ForegroundColor $sockColor
                Write-Host ("{0,-28}" -f $ps.Scope) -ForegroundColor Gray
            }
        }

        # 6. LLM ENGINES & INFERENCE SPEED (Falls LLMs aktiv)
        if ($hw.Instances.Count -gt 0) {
            Write-Host ""
            Write-Host "  LLM ENGINES & INFERENCE SPEED:" -ForegroundColor White
            Write-Host ("  {0,-8}{1,-20}{2,-10}{3,-10}{4,-12}{5,-25}{6,-21}" -f "PORT", "MODEL / ENGINE", "SLOTS", "CONTEXT", "VRAM/RAM", "TOKENS IN (INPUT)", "TOKENS OUT (GEN)") -ForegroundColor Gray
            Write-Host $subSep -ForegroundColor DarkGray
            
            foreach ($inst in $hw.Instances) {
                $slotColor = if ($inst.SlotsNum -gt 1) { "Green" } else { "DarkGray" }
                Write-Host "  " -NoNewline
                Write-Host ("{0,-8}" -f $inst.Port) -NoNewline -ForegroundColor Yellow
                Write-Host ("{0,-20}" -f $inst.Model) -NoNewline -ForegroundColor White
                Write-Host ("{0,-10}" -f $inst.Slots) -NoNewline -ForegroundColor $slotColor
                Write-Host ("{0,-10}" -f $inst.Ctx) -NoNewline -ForegroundColor Gray
                Write-Host ("{0,-12}" -f $inst.Vram) -NoNewline -ForegroundColor Magenta
                Write-Host ("{0,-25}" -f $inst.PromptSpeed) -NoNewline -ForegroundColor DarkYellow
                Write-Host ("{0,-21}" -f $inst.GenSpeed) -ForegroundColor Cyan
            }

            # Speed Statistics per Port (Min / Max / Avg / Median)
            foreach ($inst in $hw.Instances) {
                $p = $inst.Port
                $pStats = if ($script:promptHistoryByPort.ContainsKey($p)) { Get-StatsSummary -list $script:promptHistoryByPort[$p] -decimals 0 } else { $null }
                $gStats = if ($script:genHistoryByPort.ContainsKey($p)) { Get-StatsSummary -list $script:genHistoryByPort[$p] -decimals 1 } else { $null }
                if ($pStats -or $gStats) {
                    Write-Host ""
                    $pTag = "Port $p ($($inst.Model)):"
                    Write-Host "  Stats $pTag" -ForegroundColor White
                    if ($pStats) {
                        Write-Host "    Tokens In:   " -NoNewline -ForegroundColor Gray
                        Write-Host ("Min: {0,5} | Max: {1,5} | Avg: {2,5} | Med: {3,5} Tok/s  (n={4})" -f $pStats.Min, $pStats.Max, $pStats.Avg, $pStats.Median, $pStats.Count) -ForegroundColor DarkYellow
                    }
                    if ($gStats) {
                        Write-Host "    Tokens Out:  " -NoNewline -ForegroundColor Gray
                        Write-Host ("Min: {0,5} | Max: {1,5} | Avg: {2,5} | Med: {3,5} Tok/s  (n={4})" -f $gStats.Min, $gStats.Max, $gStats.Avg, $gStats.Median, $gStats.Count) -ForegroundColor Cyan
                    }
                }
            }
            if ([DateTime]::Now -lt $script:resetNoticeUntil) {
                Write-Host ""
                Write-Host "  [>> Statistiken zurueckgesetzt! <<]" -ForegroundColor Green
            }
        }

        # 7. ACTIVE PARALLEL CLIENTS & WORKERS
        $clientCount = $hw.Clients.Count
        Write-Host ""
        Write-Host "  ACTIVE CLIENTS & PARALLEL WORKERS: " -NoNewline -ForegroundColor White
        Write-Host "[$clientCount parallel verbunden]" -ForegroundColor $(if ($clientCount -gt 0) { "Yellow" } else { "DarkGray" })
        Write-Host ("  {0,-8}{1,-14}{2,-48}{3,-16}{4,-16}" -f "PID", "CLIENT", "CONNECTED SERVICES / TARGETS", "MEMORY", "CPU TIME") -ForegroundColor Gray
        Write-Host $subSep -ForegroundColor DarkGray

        if ($clientCount -eq 0) {
            Write-Host "  [Keine aktiven Client-Sockets auf den ueberwachten Ports]" -ForegroundColor DarkGray
        } else {
            foreach ($c in $hw.Clients) {
                Write-Host "  " -NoNewline
                Write-Host ("{0,-8}" -f $c.PID) -NoNewline -ForegroundColor White
                Write-Host ("{0,-14}" -f $c.Name) -NoNewline -ForegroundColor Cyan
                $dispTarget = if ($c.Target.Length -gt 46) { $c.Target.Substring(0, 43) + "..." } else { $c.Target }
                Write-Host ("{0,-48}" -f $dispTarget) -NoNewline -ForegroundColor Yellow
                Write-Host ("{0,-16}" -f ("{0:N1} MB" -f $c.MemMB)) -NoNewline -ForegroundColor White
                Write-Host ("{0,-16}" -f ("{0:N1} s" -f $c.CpuSec)) -ForegroundColor Gray
            }
        }

        
        # 8. SYSTEM HEALTH & CONFIG ADVISOR
        $advisories = [System.Collections.Generic.List[PSCustomObject]]::new()

        # Update recent worker activity window (6 seconds grace period for HTTP keep-alives)
        if (-not $script:recentWorkersByPort) { $script:recentWorkersByPort = @{} }
        $nowDt = [DateTime]::Now
        foreach ($c in $hw.Clients) {
            foreach ($p in $c.TargetPorts) {
                if (-not $script:recentWorkersByPort.ContainsKey($p)) {
                    $script:recentWorkersByPort[$p] = @{}
                }
                $script:recentWorkersByPort[$p][$c.PID] = $nowDt
            }
        }
        foreach ($p in @($script:recentWorkersByPort.Keys)) {
            $expPids = @()
            foreach ($pidNum in $script:recentWorkersByPort[$p].Keys) {
                if (($nowDt - $script:recentWorkersByPort[$p][$pidNum]).TotalSeconds -gt 6) {
                    $expPids += $pidNum
                }
            }
            foreach ($pidNum in $expPids) {
                [void]$script:recentWorkersByPort[$p].Remove($pidNum)
            }
        }

        # Check: Worker to Slot Bottleneck
        foreach ($inst in $hw.Instances) {
            $p = $inst.Port
            $workerCount = if ($script:recentWorkersByPort.ContainsKey($p)) { $script:recentWorkersByPort[$p].Count } else { 0 }
            $slots = $inst.SlotsNum

            if ($workerCount -gt $slots) {
                $diff = $workerCount - $slots
                $advisories.Add([PSCustomObject]@{
                    Level = "WARN"
                    Icon  = "[!]"
                    Color = "Yellow"
                    Title = "CONCURRENCY BOTTLENECK (Port $p)"
                    Msg   = "$workerCount workers active vs. $slots Ollama slot(s)! $diff worker(s) queued. Run 'setx OLLAMA_NUM_PARALLEL $workerCount' to enable continuous batching."
                })
            } elseif ($workerCount -gt 1 -and $slots -ge $workerCount) {
                $advisories.Add([PSCustomObject]@{
                    Level = "INFO"
                    Icon  = "[*]"
                    Color = "Green"
                    Title = "CONTINUOUS BATCHING OPTIMAL (Port $p)"
                    Msg   = "$workerCount workers multiplexing seamlessly across $slots GPU slots. Zero queue latency."
                })
            } elseif ($workerCount -eq 1) {
                $advisories.Add([PSCustomObject]@{
                    Level = "INFO"
                    Icon  = "[*]"
                    Color = "Green"
                    Title = "DEDICATED INFERENCE (Port $p)"
                    Msg   = "1 active worker running with full dedicated GPU throughput ($slots slot configured)."
                })
            }
        }

        # Check: High VRAM Usage
        if ($hw.GpuFound -and $hw.VramTot -gt 0) {
            $vramPct = ($hw.VramUsed / $hw.VramTot) * 100.0
            if ($vramPct -ge 95.0) {
                $advisories.Add([PSCustomObject]@{
                    Level = "ALERT"
                    Icon  = "[!]"
                    Color = "Red"
                    Title = "CRITICAL VRAM ALLOCATION"
                    Msg   = ("VRAM at {0:N1}% ({1:N2} / {2:N2} GB). Risk of OOM or partial CPU offload if context expands!" -f $vramPct, $hw.VramUsed, $hw.VramTot)
                })
            } elseif ($vramPct -ge 88.0) {
                $advisories.Add([PSCustomObject]@{
                    Level = "INFO"
                    Icon  = "[*]"
                    Color = "Cyan"
                    Title = "HIGH VRAM SATURATION"
                    Msg   = ("VRAM at {0:N1}% ({1:N2} / {2:N2} GB). Optimal high-density GPU utilization." -f $vramPct, $hw.VramUsed, $hw.VramTot)
                })
            }
        }

        # Check: Context Window Size
        foreach ($inst in $hw.Instances) {
            if ($inst.Ctx -ne "-" -and [int64]$inst.Ctx -ge 32768) {
                $advisories.Add([PSCustomObject]@{
                    Level = "INFO"
                    Icon  = "[i]"
                    Color = "Cyan"
                    Title = "EXTENDED CONTEXT (Port $($inst.Port))"
                    Msg   = "$($inst.Ctx) tokens configured. Flash Attention recommended to conserve KV-cache VRAM."
                })
                break
            }
        }

        # Check: Dual-Acceleration Architecture
        $cudaActive = ($hw.Instances | Where-Object { $_.Port -eq 11434 -and $_.Status -eq "Active" })
        $igpuActive = ($hw.Instances | Where-Object { $_.Port -eq 11435 -and $_.Status -eq "Active" })
        if ($cudaActive -and $igpuActive) {
            $advisories.Add([PSCustomObject]@{
                Level = "INFO"
                Icon  = "[*]"
                Color = "Green"
                Title = "HETEROGENEOUS HYBRID INFERENCE"
                Msg   = "NVIDIA discrete GPU (CUDA) and Intel integrated GPU (Vulkan) inferencing concurrently."
            })
        } elseif ($hw.NpuFound -and -not $igpuActive) {
            $advisories.Add([PSCustomObject]@{
                Level = "INFO"
                Icon  = "[i]"
                Color = "DarkGray"
                Title = "NPU CO-PROCESSOR"
                Msg   = "$($hw.NpuName) idle. Secondary Ollama instance can offload tasks via Vulkan or DirectML."
            })
        }

        Write-Host ""
        Write-Host "  SYSTEM HEALTH & CONFIG ADVISOR:" -ForegroundColor White
        Write-Host $subSep -ForegroundColor DarkGray

        $critAdvisories = $advisories | Where-Object { $_.Level -in @('WARN', 'ALERT') }
        if ($critAdvisories -and $critAdvisories.Count -gt 0) {
            foreach ($adv in $critAdvisories) {
                # Entire line colored as requested for warnings and errors
                Write-Host ("  {0} {1}: {2}" -f $adv.Icon, $adv.Title, $adv.Msg) -ForegroundColor $adv.Color
            }
        } else {
            # Normal state: show clear, meaningful concurrency & engine health (max 2 concise lines)
            $engineAdv = $advisories | Where-Object { $_.Title -match 'CONTINUOUS|DEDICATED|BOTTLENECK' }
            if ($engineAdv) {
                foreach ($adv in $engineAdv) {
                    Write-Host ("  {0} {1}: {2}" -f $adv.Icon, $adv.Title, $adv.Msg) -ForegroundColor Green
                }
            } else {
                Write-Host "  [*] All inference engines and database services running optimal. No bottlenecks." -ForegroundColor Green
            }
        }

        # 9. RECENT LOG OUTPUT (Falls gepiped)
        if ($recentLines.Count -gt 0) {
            Write-Host ""
            Write-Host $subSep -ForegroundColor DarkCyan
            Write-Host "  RECENT OUTPUT:" -ForegroundColor White
            foreach ($l in $recentLines) {
                $display = if ($l.Length -gt ($dashWidth - 6)) { $l.Substring(0, $dashWidth - 9) + "..." } else { $l }
                Write-Host "  > $display" -ForegroundColor Gray
            }
        }

        $uUml = [string][char]0x00FC
        Write-Host $mainSep -ForegroundColor Cyan
        Write-Host "  Frank Gl${uUml}ck (Gl${uUml}ck IT)  |  https://dozent.net  |  GitHub: glueck-it/ollama-top  |  [R] Reset" -ForegroundColor DarkGray
    }

    Check-KeyboardInput
    Update-Sensors
    Render-Dashboard
}

process {
    Check-KeyboardInput
    if ($_ -ne $null) {
        $line = $_.ToString().TrimEnd()
        if ($line) {
            $recentLines.Enqueue($line)
            while ($recentLines.Count -gt $maxRecentLines) {
                [void]$recentLines.Dequeue()
            }

            if ($line -match '(?<!\d)(\d+)\s*(?:/|of)\s*(\d+)(?!\d)') {
                $currentCount = [int]$matches[1]
                if ($totalCount -le 0 -or $totalCount -lt [int]$matches[2]) {
                    $totalCount = [int]$matches[2]
                }
            } elseif ($line -match '(\d{1,3}(?:\.\d+)?)\s*%') {
                $pctVal = [double]$matches[1]
                if ($totalCount -gt 0) {
                    $currentCount = [int](($pctVal / 100.0) * $totalCount)
                }
            } else {
                if ($Total -gt 0 -and -not ($line -match '^\s*$')) {
                    $currentCount++
                }
            }
        }
    }

    if ($lastHwPoll.ElapsedMilliseconds -ge $RefreshMs) {
        Update-Sensors
        Render-Dashboard
        $lastHwPoll.Restart()
    }
}

end {
    if ($MyInvocation.ExpectingInput -eq $false -or ($currentCount -eq 0 -and $recentLines.Count -eq 0 -and $InputObject -eq $null)) {
        while ($true) {
            Check-KeyboardInput
            Update-Sensors
            Render-Dashboard
            $sleepSw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($sleepSw.ElapsedMilliseconds -lt $RefreshMs) {
                if ([Console]::KeyAvailable) {
                    Check-KeyboardInput
                    Render-Dashboard
                }
                Start-Sleep -Milliseconds 50
            }
        }
    } else {
        Check-KeyboardInput
        Update-Sensors
        Render-Dashboard
        Write-Host "`n  Job abgeschlossen in $(Format-Duration $startTime.Elapsed)!" -ForegroundColor Green
    }
}
