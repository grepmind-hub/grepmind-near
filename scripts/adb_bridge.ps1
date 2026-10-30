# ADB TCP Bridge: Bridges WSL2 (172.18.160.1:5037) to Windows ADB Server (127.0.0.1:5037)
param(
    [string]$BindIp = "172.18.160.1",
    [int]$BindPort = 5037,
    [string]$TargetIp = "127.0.0.1",
    [int]$TargetPort = 5037
)

$localEndpoint = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($BindIp), $BindPort)
$listener = [System.Net.Sockets.TcpListener]::new($localEndpoint)
$listener.Start()
Write-Host "Bridge active: listening on $BindIp`:$BindPort -> $TargetIp`:$TargetPort"

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        [System.Threading.ThreadPool]::QueueUserWorkItem({
            param($state)
            $c = $state[0]
            $tIp = $state[1]
            $tPort = $state[2]
            $target = $null
            try {
                $target = [System.Net.Sockets.TcpClient]::new()
                $target.Connect($tIp, $tPort)
                $s1 = $c.GetStream()
                $s2 = $target.GetStream()

                $t1 = $s1.CopyToAsync($s2)
                $t2 = $s2.CopyToAsync($s1)
                [System.Threading.Tasks.Task]::WaitAny($t1, $t2) | Out-Null
            } catch {
            } finally {
                if ($c) { $c.Dispose() }
                if ($target) { $target.Dispose() }
            }
        }, @($client, $TargetIp, $TargetPort)) | Out-Null
    }
} finally {
    $listener.Stop()
}
