Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Bitmap]::FromFile('C:\Users\srika\.gemini\antigravity-ide\brain\087e06af-7991-45cb-882c-2cb5c2e78845\current_screen.png')
Write-Host "Image size: $($bmp.Width) x $($bmp.Height)"
for ($y = 650; $y -lt 1200; $y += 5) {
    for ($x = 700; $x -lt 900; $x += 5) {
        $c = $bmp.GetPixel($x, $y)
        if ($c.R -lt 50 -and $c.G -gt 70 -and $c.B -gt 200) {
            Write-Host "Found icon at $x, $y : R=$($c.R) G=$($c.G) B=$($c.B)"
        }
    }
}
$bmp.Dispose()
