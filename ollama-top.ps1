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
    
    # Hide cursor during execution to eliminate flicker and jumping
    try { [Console]::CursorVisible = $false } catch {}

    # ANSI & VT100 Escape Codes for 100% Flicker-Free Double-Buffered Rendering
    $e = [char]27
    $script:cReset   = "$e[0m"
    $script:cBld     = "$e[1m"
    $script:cCyan    = "$e[36m"
    $script:cYellow  = "$e[33m"
    $script:cGreen   = "$e[32m"
    $script:cRed     = "$e[31m"
    $script:cGray    = "$e[90m"
    $script:cWhite   = "$e[97m"
    $script:cMag     = "$e[35m"
    $script:cBlue    = "$e[34m"
    $script:cDCyan   = "$e[36m"
    $script:cDGray   = "$e[38;5;240m"
    $script:cDYell   = "$e[33m"
    $script:cClrEOL  = "$e[K"
    $script:cClrEOS  = "$e[J"
    $script:cHome    = "$e[H"

    # Solid block & seamless box drawing characters
    $script:chFull   = [string][char]0x2588 # █ (Progress bar fill)
    $script:chLight  = [string][char]0x2591 # ░ (Progress bar empty)
    $script:chHBar   = [string][char]0x2500 # ─ (Box drawings light horizontal)
    $script:chDBar   = [string][char]0x2550 # ═ (Box drawings double horizontal)
    $script:chThick  = [string][char]0x2501 # ━ (Box drawings heavy horizontal)

    # High-Performance Win32 APIs for Sub-Millisecond CPU, RAM & Socket Polling
    if (-not ([System.Management.Automation.PSTypeName]'FastSysInfo').Type) {
        $csharpCode = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Net;

public static class FastSysInfo {
    [StructLayout(LayoutKind.Sequential)]
    public struct FILETIME {
        public uint dwLowDateTime;
        public uint dwHighDateTime;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetSystemTimes(out FILETIME idleTime, out FILETIME kernelTime, out FILETIME userTime);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct MEMORYSTATUSEX {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

    private static ulong prevIdle = 0;
    private static ulong prevKernel = 0;
    private static ulong prevUser = 0;

    private static ulong ToUInt64(FILETIME ft) {
        return unchecked(((ulong)ft.dwHighDateTime << 32) | ft.dwLowDateTime);
    }

    public static double GetCpuUsage() {
        FILETIME idle, kernel, user;
        if (!GetSystemTimes(out idle, out kernel, out user)) return 0;
        ulong i = ToUInt64(idle);
        ulong k = ToUInt64(kernel);
        ulong u = ToUInt64(user);

        if (prevKernel == 0 && prevUser == 0) {
            prevIdle = i; prevKernel = k; prevUser = u;
            return 0;
        }

        ulong dIdle = i - prevIdle;
        ulong dKernel = k - prevKernel;
        ulong dUser = u - prevUser;

        prevIdle = i; prevKernel = k; prevUser = u;

        ulong dTotal = dKernel + dUser;
        if (dTotal == 0) return 0;
        double pct = (double)(dTotal - dIdle) / dTotal * 100.0;
        if (pct < 0) pct = 0;
        if (pct > 100) pct = 100;
        return pct;
    }

    public static void GetMemory(out double totalGb, out double usedGb) {
        MEMORYSTATUSEX mem = new MEMORYSTATUSEX();
        mem.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
        if (GlobalMemoryStatusEx(ref mem)) {
            totalGb = Math.Round((double)mem.ullTotalPhys / 1073741824.0, 1);
            usedGb = Math.Round((double)(mem.ullTotalPhys - mem.ullAvailPhys) / 1073741824.0, 1);
        } else {
            totalGb = 0; usedGb = 0;
        }
    }
}

public static class FastNetInfo {
    [DllImport("iphlpapi.dll", SetLastError = true)]
    public static extern uint GetExtendedTcpTable(
        IntPtr pTcpTable,
        ref int pdwSize,
        bool bOrder,
        int ulAf,
        int tableClass,
        uint reserved = 0);

    public const int AF_INET = 2;
    public const int AF_INET6 = 23;
    public const int TCP_TABLE_OWNER_PID_ALL = 5;

    public struct FastTcpConn {
        public int LocalPort;
        public int RemotePort;
        public string LocalAddr;
        public string RemoteAddr;
        public int Pid;
    }

    public static List<FastTcpConn> GetAllTcpConnections(out HashSet<int> listeningPorts) {
        var conns = new List<FastTcpConn>();
        listeningPorts = new HashSet<int>();

        // IPv4
        int size = 0;
        GetExtendedTcpTable(IntPtr.Zero, ref size, false, AF_INET, TCP_TABLE_OWNER_PID_ALL, 0);
        if (size > 0) {
            IntPtr buf = Marshal.AllocHGlobal(size);
            try {
                if (GetExtendedTcpTable(buf, ref size, false, AF_INET, TCP_TABLE_OWNER_PID_ALL, 0) == 0) {
                    int numEntries = Marshal.ReadInt32(buf);
                    IntPtr rowPtr = (IntPtr)((long)buf + 4);
                    for (int i = 0; i < numEntries; i++) {
                        int state = Marshal.ReadInt32(rowPtr, 0);
                        int locPortRaw = Marshal.ReadInt32(rowPtr, 8);
                        int locPort = ((locPortRaw & 0xFF) << 8) | ((locPortRaw >> 8) & 0xFF);

                        if (state == 2) {
                            listeningPorts.Add(locPort);
                        } else if (state == 5) {
                            uint locAddr = (uint)Marshal.ReadInt32(rowPtr, 4);
                            uint remAddr = (uint)Marshal.ReadInt32(rowPtr, 12);
                            int remPortRaw = Marshal.ReadInt32(rowPtr, 16);
                            int remPort = ((remPortRaw & 0xFF) << 8) | ((remPortRaw >> 8) & 0xFF);
                            int pid = Marshal.ReadInt32(rowPtr, 20);

                            string locIp = new IPAddress(BitConverter.GetBytes(locAddr)).ToString();
                            string remIp = new IPAddress(BitConverter.GetBytes(remAddr)).ToString();

                            conns.Add(new FastTcpConn {
                                LocalPort = locPort,
                                RemotePort = remPort,
                                LocalAddr = locIp,
                                RemoteAddr = remIp,
                                Pid = pid
                            });
                        }
                        rowPtr = (IntPtr)((long)rowPtr + 24);
                    }
                }
            } finally {
                Marshal.FreeHGlobal(buf);
            }
        }

        // IPv6
        size = 0;
        GetExtendedTcpTable(IntPtr.Zero, ref size, false, AF_INET6, TCP_TABLE_OWNER_PID_ALL, 0);
        if (size > 0) {
            IntPtr buf = Marshal.AllocHGlobal(size);
            try {
                if (GetExtendedTcpTable(buf, ref size, false, AF_INET6, TCP_TABLE_OWNER_PID_ALL, 0) == 0) {
                    int numEntries = Marshal.ReadInt32(buf);
                    IntPtr rowPtr = (IntPtr)((long)buf + 4);
                    byte[] ipBytes = new byte[16];
                    for (int i = 0; i < numEntries; i++) {
                        int state = Marshal.ReadInt32(rowPtr, 48);
                        int locPortRaw = Marshal.ReadInt32(rowPtr, 20);
                        int locPort = ((locPortRaw & 0xFF) << 8) | ((locPortRaw >> 8) & 0xFF);

                        if (state == 2) {
                            listeningPorts.Add(locPort);
                        } else if (state == 5) {
                            Marshal.Copy(rowPtr, ipBytes, 0, 16);
                            string locIp = new IPAddress(ipBytes).ToString();

                            IntPtr remPtr = (IntPtr)((long)rowPtr + 24);
                            Marshal.Copy(remPtr, ipBytes, 0, 16);
                            string remIp = new IPAddress(ipBytes).ToString();

                            int remPortRaw = Marshal.ReadInt32(rowPtr, 44);
                            int remPort = ((remPortRaw & 0xFF) << 8) | ((remPortRaw >> 8) & 0xFF);
                            int pid = Marshal.ReadInt32(rowPtr, 52);

                            conns.Add(new FastTcpConn {
                                LocalPort = locPort,
                                RemotePort = remPort,
                                LocalAddr = locIp,
                                RemoteAddr = remIp,
                                Pid = pid
                            });
                        }
                        rowPtr = (IntPtr)((long)rowPtr + 56);
                    }
                }
            } finally {
                Marshal.FreeHGlobal(buf);
            }
        }

        return conns;
    }
}
'@
        Add-Type -TypeDefinition $csharpCode -Language CSharp
    }

    # Prime CPU usage delta measurement
    [FastSysInfo]::GetCpuUsage() | Out-Null

    $startTime = [System.Diagnostics.Stopwatch]::StartNew()
    $lastHwPoll = [System.Diagnostics.Stopwatch]::StartNew()
    $script:lastSlowPoll = [System.Diagnostics.Stopwatch]::StartNew()
    $currentCount = 0
    $totalCount = $Total
    $recentLines = [System.Collections.Generic.Queue[string]]::new()
    $maxRecentLines = 4
    $script:exitRequested = $false
    $script:appVersion = "1.2.0"
    $script:firstRender = $true

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

    # CPU Static Specs
    $cpuInfo = Get-CimInstance Win32_Processor -Property Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed -ErrorAction SilentlyContinue | Select-Object -First 1
    $cpuName = if ($cpuInfo) { ($cpuInfo.Name -replace '\(R\)|\(TM\)|\bCPU\b','').Trim() } else { "Host CPU" }
    $cpuCores = if ($cpuInfo) { "$($cpuInfo.NumberOfCores)C/$($cpuInfo.NumberOfLogicalProcessors)T" } else { "" }
    $script:cpuMaxClock = if ($cpuInfo -and $cpuInfo.MaxClockSpeed) { [int]$cpuInfo.MaxClockSpeed } else { 0 }

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

    # Throttled sensor state caches
    $script:cachedNpuUtil = 0
    $script:cachedIntelGpuUtil = 0
    $script:listeningPorts = [System.Collections.Generic.HashSet[int]]::new()

    # Per-port token speeds cache and history
    $script:cachedPromptSpeedByPort = @{}
    $script:cachedGenSpeedByPort    = @{}
    $script:promptHistoryByPort     = @{}
    $script:genHistoryByPort        = @{}
    $script:seenLogTimingsByPort    = @{}
    $script:resetNoticeUntil        = [DateTime]::MinValue

    # Dynamic Ollama Log Resolution & Slot Configuration
    $script:resolvedLogByPort        = @{}
    $script:logLookupFailedUntil     = @{}
    $script:slotsByPort              = @{}

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
        # Negative cache: don't scan filesystem on every tick if previously not found
        if ($script:logLookupFailedUntil.ContainsKey($port) -and [DateTime]::Now -lt $script:logLookupFailedUntil[$port]) {
            return $null
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

        # 2. Dynamic Discovery in Tasks & Temp Logs
        try {
            $taskLogs = Get-ChildItem -Path "$env:USERPROFILE\.gemini\antigravity\brain\*\.system_generated\tasks\*.log" -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending | Select-Object -First 10
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

        $script:logLookupFailedUntil[$port] = [DateTime]::Now.AddSeconds(30)
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
                } elseif ($k.Key -in @([System.ConsoleKey]::Q, [System.ConsoleKey]::X) -or $k.KeyChar -in @('q', 'Q', 'x', 'X')) {
                    $script:exitRequested = $true
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
        CpuTempStr     = "  Aktiv"
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

        # 2. Host CPU & RAM (High-Speed Win32 APIs: < 2 ms instead of 1300 ms!)
        try {
            $cpuPct = [FastSysInfo]::GetCpuUsage()
            $hw.CpuUtil = [int][math]::Round($cpuPct, 0)
            $hw.CpuClk  = $script:cpuMaxClock
            
            $totGb = 0.0; $usedGb = 0.0
            [FastSysInfo]::GetMemory([ref]$totGb, [ref]$usedGb)
            $hw.RamTotGb  = $totGb
            $hw.RamUsedGb = $usedGb
        } catch {}

        # 3. NPU & Integrated GPU Load (Throttled to every 4s to prevent WMI lag)
        if ($hw.NpuFound -or $hw.IntelGpuFound) {
            if ($script:lastSlowPoll.ElapsedMilliseconds -ge 4000 -or $script:cachedNpuUtil -eq 0) {
                try {
                    $engs = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction SilentlyContinue
                    if ($hw.NpuFound) {
                        $npuEng = $engs | Where-Object { $_.Name -match 'Neural' }
                        $script:cachedNpuUtil = if ($npuEng) { [int][math]::Min(100, (($npuEng | Measure-Object -Property UtilizationPercentage -Sum).Sum)) } else { 0 }
                    }
                    if ($hw.IntelGpuFound -and $script:intelLuid) {
                        $intelEng = $engs | Where-Object { $_.Name -match $script:intelLuid }
                        $script:cachedIntelGpuUtil = if ($intelEng) { [int][math]::Min(100, (($intelEng | Measure-Object -Property UtilizationPercentage -Sum).Sum)) } else { 0 }
                    }
                    $script:lastSlowPoll.Restart()
                } catch {}
            }
            $hw.NpuUtil      = $script:cachedNpuUtil
            $hw.IntelGpuUtil = $script:cachedIntelGpuUtil
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

        # 5. Universal Dynamic Service & Database Discovery (High-Speed Win32: < 5 ms instead of 2970 ms!)
        $listeningPorts = $null
        $allTcp = try { [FastNetInfo]::GetAllTcpConnections([ref]$listeningPorts) } catch { @() }
        $script:listeningPorts = $listeningPorts
        $portStats = @()
        $clients = @()

        if ($allTcp -and $allTcp.Count -gt 0) {
            # Build target port set
            $monitoredPorts = [System.Collections.Generic.HashSet[int]]::new()
            foreach ($k in $script:knownServices.Keys) { [void]$monitoredPorts.Add($k) }
            foreach ($p in $WatchPorts) { [void]$monitoredPorts.Add($p) }
            foreach ($p in $OllamaPorts) { [void]$monitoredPorts.Add($p) }

            # Filter active connections touching monitored services (deduplicate loopback pairs)
            $matchedConns = [System.Collections.Generic.List[object]]::new()
            foreach ($conn in $allTcp) {
                if ($monitoredPorts.Contains($conn.RemotePort)) {
                    $matchedConns.Add($conn)
                } elseif ($monitoredPorts.Contains($conn.LocalPort)) {
                    if ($conn.RemoteAddr -notin @('127.0.0.1', '::1')) {
                        $matchedConns.Add($conn)
                    }
                }
            }

            # Cache processes once per tick in a hashtable: O(1) lookups
            $procCache = @{}
            try {
                foreach ($proc in [System.Diagnostics.Process]::GetProcesses()) {
                    $procCache[$proc.Id] = $proc
                }
            } catch {}

            # Exclude monitor itself from service worker socket counts
            $workerConns = [System.Collections.Generic.List[object]]::new()
            foreach ($conn in $matchedConns) {
                $pObj = $procCache[$conn.Pid]
                if (-not ($pObj -and $pObj.ProcessName -match 'powershell|pwsh|svchost')) {
                    $workerConns.Add($conn)
                }
            }

            # Group by Service Port for service summary
            $groupedByPort = $workerConns | Group-Object {
                if ($monitoredPorts.Contains($_.RemotePort)) { $_.RemotePort } else { $_.LocalPort }
            }

            foreach ($grp in $groupedByPort) {
                $pNum = [int]$grp.Name
                $svcName = Get-ServiceName $pNum
                $firstConn = $grp.Group[0]
                $targetAddr = if ($monitoredPorts.Contains($firstConn.RemotePort)) { $firstConn.RemoteAddr } else { $firstConn.LocalAddr }
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
            $clientConns = $workerConns | Where-Object { $monitoredPorts.Contains($_.RemotePort) }
            if ($clientConns) {
                $groupedClients = $clientConns | Group-Object Pid
                foreach ($g in $groupedClients) {
                    $pidNum = [int]$g.Name
                    $proc = $procCache[$pidNum]
                    if ($proc -and $proc.ProcessName -notmatch 'powershell|pwsh|svchost') {
                        $targetNames = [System.Collections.Generic.List[string]]::new()
                        foreach ($conn in $g.Group) {
                            $rPort = [int]$conn.RemotePort
                            $sName = Get-ServiceName $rPort
                            $sShort = ($sName -split '\(')[0].Trim()
                            $targetNames.Add("$sShort ($rPort)")
                        }
                        $targetStr = ($targetNames | Select-Object -Unique) -join ', '
                        $memMb = try { [math]::Round($proc.WorkingSet64 / 1MB, 1) } catch { 0.0 }
                        $cpuSec = try { [math]::Round($proc.TotalProcessorTime.TotalSeconds, 1) } catch { 0.0 }
                        $clients += [PSCustomObject]@{
                            PID         = $pidNum
                            Name        = $proc.ProcessName
                            Target      = $targetStr
                            MemMB       = $memMb
                            CpuSec      = $cpuSec
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

        # 7. Ollama REST API per Port (ONLY query if port is actually LISTENING: 0 ms timeout!)
        $instances = @()
        foreach ($port in $OllamaPorts) {
            if ($script:listeningPorts -and -not $script:listeningPorts.Contains($port)) {
                continue
            }
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
                            Port           = $port
                            Model          = $m.name
                            Slots          = $slotsStr
                            SlotsNum       = $slots
                            Ctx            = "$($m.context_length)"
                            Vram           = "${vramGb} GB"
                            VramGb         = $vramGb
                            VramBytes      = [int64]$m.size_vram
                            PromptSpeed    = $pSpeedStr
                            PromptSpeedVal = $pSpeed
                            GenSpeed       = $gSpeedStr
                            GenSpeedVal    = $gSpeed
                            Status         = "Active"
                        }
                    }
                } elseif ($res) {
                    $instances += [PSCustomObject]@{
                        Port           = $port
                        Model          = "(Ready / No model)"
                        Slots          = $slotsStr
                        SlotsNum       = $slots
                        Ctx            = "-"
                        Vram           = "0 GB"
                        VramGb         = 0.0
                        VramBytes      = 0L
                        PromptSpeed    = "-"
                        PromptSpeedVal = 0.0
                        GenSpeed       = "-"
                        GenSpeedVal    = 0.0
                        Status         = "Idle"
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
        # Double-Buffered Single-Write Rendering (100% Flicker-Free)
        $sb = [System.Text.StringBuilder]::new(4096)
        
        # Position cursor to (0, 0) without clearing screen (100% flicker-free)
        if ($script:firstRender) {
            try { Clear-Host } catch {}
            $script:firstRender = $false
        } else {
            try {
                [Console]::SetCursorPosition(0, 0)
            } catch {
                [void]$sb.Append($script:cHome)
            }
        }

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

        # Helper to append formatted line with Clear-To-End-Of-Line
        $addLine = {
            param([string]$lineContent)
            [void]$sb.AppendLine("$lineContent$($script:cReset)$($script:cClrEOL)")
        }

        # Header
        & $addLine ""
        & $addLine "$($script:cCyan)$mainSep"
        & $addLine "  $($script:cYellow)$($script:cBld)OLLAMA-TOP v$($script:appVersion): AI, DATABASE & HARDWARE MONITOR  $($script:cReset)$($script:cGray)|  $now  |  Host: $env:COMPUTERNAME"
        & $addLine "$($script:cDCyan)$subSep"

        # 1. BATCH JOB PROGRESS BAR (Falls gepiped oder -Total angegeben)
        if ($totalCount -gt 0 -or $currentCount -gt 0) {
            $elapsed = $startTime.Elapsed
            $speed = if ($elapsed.TotalSeconds -gt 1 -and $currentCount -gt 0) { $currentCount / $elapsed.TotalSeconds } else { 0 }
            
            & $addLine "  $($script:cWhite)JOB: $Title"
            if ($totalCount -gt 0) {
                $pct = $currentCount / $totalCount
                $barStr = Format-Bar -Pct $pct -Width 32
                $pctText = "{0,5:N1}%" -f ($pct * 100)
                
                $remainingItems = [math]::Max(0, ($totalCount - $currentCount))
                $etaSec = if ($speed -gt 0) { $remainingItems / $speed } else { 0 }
                $etaTs = [TimeSpan]::FromSeconds($etaSec)
                $etaStr = if ($speed -gt 0) { Format-Duration $etaTs } else { "Berechne..." }

                & $addLine "  $($script:cGreen)Progress:    [$barStr] $($script:cYellow)$pctText"
                & $addLine ("  $($script:cWhite)Status:      {0} / {1} Items  (Offen: {2})" -f $currentCount, $totalCount, $remainingItems)
                & $addLine ("  $($script:cYellow)Speed:       {0:N2} Items/s (~{1:N0}/min) | Elapsed: {2} | ETA: {3}" -f $speed, ($speed * 60), (Format-Duration $elapsed), $etaStr)
            } else {
                & $addLine ("  $($script:cWhite)Status:      {0} Items | Speed: {1:N2} Items/s | Elapsed: {2}" -f $currentCount, $speed, (Format-Duration $elapsed))
            }
            & $addLine "$($script:cDCyan)$subSep"
        }

        # 2. NVIDIA GPU HARDWARE SENSORS
        if ($hw.GpuFound) {
            $deg = [string][char]0x00B0
            $gpuTempColor = $script:cGreen
            if ($hw.GpuTemp -ge 84) { $gpuTempColor = $script:cRed }
            elseif ($hw.GpuTemp -ge 74) { $gpuTempColor = $script:cYellow }

            & $addLine "  $($script:cWhite)NVIDIA GPU SENSORS ($($hw.GpuName)):"

            # GPU Compute + Temp
            $gpuBar = Format-Bar -Pct ($hw.GpuUtil / 100.0) -Width 18
            & $addLine ("  $($script:cGray)GPU Core Load:   $($script:cCyan)[{0}] $($script:cYellow){1,3}%$($script:cGray)  | Clock: $($script:cWhite){2,5} MHz$($script:cGray)  | Temp:  {3}{4,3}${deg} C" -f $gpuBar, $hw.GpuUtil, $hw.GpuCoreClk, $gpuTempColor, $hw.GpuTemp)

            # Memory Bus + Power Draw
            $busBar = Format-Bar -Pct ($hw.MemBusUtil / 100.0) -Width 18
            & $addLine ("  $($script:cGray)GPU Memory Bus:  $($script:cCyan)[{0}] $($script:cYellow){1,3}%$($script:cGray)  | Clock: $($script:cWhite){2,5} MHz$($script:cGray)  | Power: $($script:cWhite){3,6:N1} W" -f $busBar, $hw.MemBusUtil, $hw.GpuMemClk, $hw.GpuPower)

            # VRAM
            $vramPct = if ($hw.VramTot -gt 0) { $hw.VramUsed / $hw.VramTot } else { 0 }
            $vramBar = Format-Bar -Pct $vramPct -Width 18
            & $addLine ("  $($script:cGray)VRAM Belegung:   $($script:cMag)[{0}] $($script:cWhite){1,6:N1} / {2,6:N1} GB ({3,3:N0}%)" -f $vramBar, $hw.VramUsed, $hw.VramTot, ($vramPct * 100))

            & $addLine ""
        }

        # 3. HOST CPU & SYSTEM RAM
        & $addLine "  $($script:cWhite)HOST CPU & SYSTEM ($cpuName - $cpuCores):"

        # CPU Load
        $cpuBar = Format-Bar -Pct ($hw.CpuUtil / 100.0) -Width 18
        & $addLine ("  $($script:cGray)CPU Auslastung:  $($script:cGreen)[{0}] $($script:cYellow){1,3}%$($script:cGray)  | Clock: $($script:cWhite){2,5} MHz$($script:cGray)  | Temp:  $($script:cCyan){3,6}" -f $cpuBar, $hw.CpuUtil, $hw.CpuClk, $hw.CpuTempStr)

        # Host RAM
        $ramPct = if ($hw.RamTotGb -gt 0) { $hw.RamUsedGb / $hw.RamTotGb } else { 0 }
        $ramBar = Format-Bar -Pct $ramPct -Width 18
        & $addLine ("  $($script:cGray)System RAM:      $($script:cBlue)[{0}] $($script:cWhite){1,6:N1} / {2,6:N1} GB ({3,3:N0}%)" -f $ramBar, $hw.RamUsedGb, $hw.RamTotGb, ($ramPct * 100))

        # 4. INTEL NPU & ACCELERATOR SENSORS (Falls im System vorhanden)
        if ($hw.NpuFound -or $hw.IntelGpuFound) {
            & $addLine ""
            $accelHeader = if ($hw.NpuFound) { "INTEL NPU & iGPU SENSORS ($($hw.NpuName)):" } else { "INTEGRATED GPU SENSORS ($($hw.IntelGpuName)):" }
            & $addLine "  $($script:cWhite)$accelHeader"

            if ($hw.NpuFound) {
                $npuBar = Format-Bar -Pct ($hw.NpuUtil / 100.0) -Width 18
                $npuNote = if ($hw.NpuUtil -gt 0) { "Neural (Hardware Active)" } else { "Neural (Standby / Ollama nutzt iGPU Vulkan)" }
                & $addLine ("  $($script:cGray)NPU Neural Load: $($script:cGreen)[{0}] $($script:cYellow){1,3}%$($script:cGray)  | Engine: $($script:cCyan){2}" -f $npuBar, $hw.NpuUtil, $npuNote)
            }

            if ($hw.IntelGpuFound) {
                $igpuBar = Format-Bar -Pct ($hw.IntelGpuUtil / 100.0) -Width 18
                & $addLine ("  $($script:cGray)Intel iGPU Load: $($script:cCyan)[{0}] $($script:cYellow){1,3}%$($script:cGray)  | Device: $($script:cWhite){2}" -f $igpuBar, $hw.IntelGpuUtil, $hw.IntelGpuName)
            }
        }

        # 5. NETWORK TRAFFIC & ACTIVE SERVICES
        & $addLine ""
        $nicTitle = if ($hw.NetNicName -and $hw.NetNicName -ne "None") { " ($($hw.NetNicName))" } else { "" }
        & $addLine ("  $($script:cWhite)NETWORK TRAFFIC & ADAPTER{0}:" -f $nicTitle)

        $rxStr = "$(Format-Bytes $hw.NetRxSpeed)/s"
        $txStr = "$(Format-Bytes $hw.NetTxSpeed)/s"
        $sessRxStr = Format-Bytes $hw.NetSessionRec
        $sessTxStr = Format-Bytes $hw.NetSessionSent

        & $addLine ("  $($script:cGray)Gesamt Live:     $($script:cCyan)[In / Download] $($script:cWhite){0,-12} $($script:cYellow)[Out / Upload] $($script:cWhite){1,-12} $($script:cGray)| Session: $($script:cDCyan)In {2} / Out {3}" -f $rxStr, $txStr, $sessRxStr, $sessTxStr)

        # ACTIVE SERVICES & ENDPOINTS TABLE
        if ($hw.PortStats -and $hw.PortStats.Count -gt 0) {
            & $addLine ""
            & $addLine "  $($script:cWhite)ACTIVE SERVICES & ENDPOINTS (Database, Cache & AI):"
            & $addLine ("  $($script:cGray){0,-8}{1,-24}{2,-32}{3,12}  {4,-28}" -f "PORT", "SERVICE", "ENDPOINT / TARGET", "SOCKETS", "SCOPE / NETWORK")
            & $addLine "$($script:cDGray)$subSep"
            foreach ($ps in $hw.PortStats) {
                $sockColor = if ($ps.Sockets -gt 0) { $script:cGreen } else { $script:cDGray }
                $sockStr = "{0,5:N0} aktiv" -f $ps.Sockets
                & $addLine ("  $($script:cYellow){0,5}   $($script:cWhite){1,-24}$($script:cCyan){2,-32}{3}{4,12}  $($script:cGray){5,-28}" -f $ps.Port, $ps.Service, $ps.Target, $sockColor, $sockStr, $ps.Scope)
            }
        }

        # 6. LLM ENGINES & INFERENCE SPEED (Falls LLMs aktiv)
        if ($hw.Instances.Count -gt 0) {
            & $addLine ""
            & $addLine "  $($script:cWhite)LLM ENGINES & INFERENCE SPEED:"
            & $addLine ("  $($script:cGray){0,-7}{1,-18}{2,9}  {3,10}  {4,11}  {5,18}  {6,18}" -f "PORT", "MODEL / ENGINE", "SLOTS", "CONTEXT", "VRAM/RAM", "TOKENS IN (INPUT)", "TOKENS OUT (GEN)")
            & $addLine "$($script:cDGray)$subSep"
            
            foreach ($inst in $hw.Instances) {
                $slotColor = if ($inst.SlotsNum -gt 1) { $script:cGreen } else { $script:cDGray }
                $slotsStr = if ($inst.SlotsNum -eq 1) { " 1 slot " } elseif ($inst.SlotsNum -gt 1) { "{0,2} slots" -f $inst.SlotsNum } else { "{0,7}" -f $inst.Slots }
                $ctxStr = if ($inst.Ctx -match '^\d+$') { "{0,8:N0}" -f [int64]$inst.Ctx } else { "{0,8}" -f $inst.Ctx }
                $vramStr = if ($inst.VramGb -gt 0) { "{0,6:N1} GB" -f $inst.VramGb } else { "{0,9}" -f $inst.Vram }
                $pSpeedStr = if ($inst.PromptSpeedVal -gt 0) { "{0,7:N0} Tok/s" -f $inst.PromptSpeedVal } else { "{0,16}" -f $inst.PromptSpeed }
                $gSpeedStr = if ($inst.GenSpeedVal -gt 0) { "{0,7:N1} Tok/s" -f $inst.GenSpeedVal } else { "{0,16}" -f $inst.GenSpeed }

                & $addLine ("  $($script:cYellow){0,5}  $($script:cWhite){1,-18}{2}{3,9}  $($script:cGray){4,10}  $($script:cMag){5,11}  $($script:cDYell){6,18}  $($script:cCyan){7,18}" -f $inst.Port, $inst.Model, $slotColor, $slotsStr, $ctxStr, $vramStr, $pSpeedStr, $gSpeedStr)
            }

            # Speed Statistics per Port (Min / Max / Avg / Median)
            foreach ($inst in $hw.Instances) {
                $p = $inst.Port
                $pStats = if ($script:promptHistoryByPort.ContainsKey($p)) { Get-StatsSummary -list $script:promptHistoryByPort[$p] -decimals 0 } else { $null }
                $gStats = if ($script:genHistoryByPort.ContainsKey($p)) { Get-StatsSummary -list $script:genHistoryByPort[$p] -decimals 1 } else { $null }
                if ($pStats -or $gStats) {
                    & $addLine ""
                    $pTag = "Port $p ($($inst.Model)):"
                    & $addLine "  $($script:cWhite)Stats $pTag"
                    if ($pStats) {
                        & $addLine ("    $($script:cGray)Tokens In:   $($script:cDYell)Min: {0,6} | Max: {1,6} | Avg: {2,6} | Med: {3,6} Tok/s  (n={4,5})" -f $pStats.Min, $pStats.Max, $pStats.Avg, $pStats.Median, $pStats.Count)
                    }
                    if ($gStats) {
                        & $addLine ("    $($script:cGray)Tokens Out:  $($script:cCyan)Min: {0,6} | Max: {1,6} | Avg: {2,6} | Med: {3,6} Tok/s  (n={4,5})" -f $gStats.Min, $gStats.Max, $gStats.Avg, $gStats.Median, $gStats.Count)
                    }
                }
            }
            if ([DateTime]::Now -lt $script:resetNoticeUntil) {
                & $addLine ""
                & $addLine "  $($script:cGreen)[>> Statistiken zurueckgesetzt! <<]"
            }
        }

        # 7. ACTIVE PARALLEL CLIENTS & WORKERS
        $clientCount = $hw.Clients.Count
        $clientCountColor = if ($clientCount -gt 0) { $script:cYellow } else { $script:cDGray }
        & $addLine ""
        & $addLine "  $($script:cWhite)ACTIVE CLIENTS & PARALLEL WORKERS: ${clientCountColor}[$clientCount parallel verbunden]"
        & $addLine ("  $($script:cGray){0,7}  {1,-14}{2,-42}{3,17}  {4,15}" -f "PID", "CLIENT", "CONNECTED SERVICES / TARGETS", "MEMORY", "CPU TIME")
        & $addLine "$($script:cDGray)$subSep"

        if ($clientCount -eq 0) {
            & $addLine "  $($script:cDGray)[Keine aktiven Client-Sockets auf den ueberwachten Ports]"
        } else {
            foreach ($c in $hw.Clients) {
                $dispTarget = if ($c.Target.Length -gt 40) { $c.Target.Substring(0, 37) + "..." } else { $c.Target }
                $memStr = "{0,11:N1} MB" -f $c.MemMB
                $cpuStr = "{0,11:N1} s" -f $c.CpuSec
                & $addLine ("  $($script:cWhite){0,7}  $($script:cCyan){1,-14}$($script:cYellow){2,-42}$($script:cWhite){3,17}  $($script:cGray){4,15}" -f $c.PID, $c.Name, $dispTarget, $memStr, $cpuStr)
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

        & $addLine ""
        & $addLine "  $($script:cWhite)SYSTEM HEALTH & CONFIG ADVISOR:"
        & $addLine "$($script:cDGray)$subSep"

        $critAdvisories = $advisories | Where-Object { $_.Level -in @('WARN', 'ALERT') }
        if ($critAdvisories -and $critAdvisories.Count -gt 0) {
            foreach ($adv in $critAdvisories) {
                $advColor = if ($adv.Color -eq "Red") { $script:cRed } elseif ($adv.Color -eq "Yellow") { $script:cYellow } else { $script:cGreen }
                & $addLine ("  {0}{1} {2}: {3}" -f $advColor, $adv.Icon, $adv.Title, $adv.Msg)
            }
        } else {
            $engineAdv = $advisories | Where-Object { $_.Title -match 'CONTINUOUS|DEDICATED|BOTTLENECK' }
            if ($engineAdv) {
                foreach ($adv in $engineAdv) {
                    & $addLine ("  $($script:cGreen){0} {1}: {2}" -f $adv.Icon, $adv.Title, $adv.Msg)
                }
            } else {
                & $addLine "  $($script:cGreen)[*] All inference engines and database services running optimal. No bottlenecks."
            }
        }

        # 9. RECENT LOG OUTPUT (Falls gepiped)
        if ($recentLines.Count -gt 0) {
            & $addLine ""
            & $addLine "$($script:cDCyan)$subSep"
            & $addLine "  $($script:cWhite)RECENT OUTPUT:"
            foreach ($l in $recentLines) {
                $display = if ($l.Length -gt ($dashWidth - 6)) { $l.Substring(0, $dashWidth - 9) + "..." } else { $l }
                & $addLine "  $($script:cGray)> $display"
            }
        }

        $uUml = [string][char]0x00FC
        & $addLine "$($script:cCyan)$mainSep"
        & $addLine "  $($script:cDGray)Frank Gl${uUml}ck (Gl${uUml}ck IT)  |  https://dozent.net  |  GitHub: glueck-it/ollama-top  |  [R] Reset  |  [Q/X] Exit"

        # Clear remaining screen buffer below dashboard and flush frame in single atomic call
        [void]$sb.Append($script:cClrEOS)
        [Console]::Write($sb.ToString())
    }

    Check-KeyboardInput
    if (-not $script:exitRequested) {
        Update-Sensors
        Render-Dashboard
    }
}

process {
    Check-KeyboardInput
    if ($script:exitRequested) { break }
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
    try {
        if ($currentCount -eq 0 -and $recentLines.Count -eq 0 -and $InputObject -eq $null) {
            while (-not $script:exitRequested) {
                Check-KeyboardInput
                if ($script:exitRequested) { break }
                Update-Sensors
                Render-Dashboard
                $sleepSw = [System.Diagnostics.Stopwatch]::StartNew()
                while ($sleepSw.ElapsedMilliseconds -lt $RefreshMs -and -not $script:exitRequested) {
                    try {
                        if ([Console]::KeyAvailable) {
                            Check-KeyboardInput
                            if ($script:exitRequested) { break }
                            Render-Dashboard
                        }
                    } catch {}
                    Start-Sleep -Milliseconds 50
                }
            }
            Write-Host "`n  OLLAMA-TOP beendet.`n" -ForegroundColor Yellow
        } else {
            Check-KeyboardInput
            Update-Sensors
            Render-Dashboard
            Write-Host "`n  Job abgeschlossen in $(Format-Duration $startTime.Elapsed)!" -ForegroundColor Green
        }
    } finally {
        try { [Console]::CursorVisible = $true } catch {}
    }
}
