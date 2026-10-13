# Raumsteuerung Sitzungszimmer 5 - kleiner Webserver fuer das Tablet
# Liefert die Dateien aus diesem Ordner auf Port 8080 aus: http://<IP dieses PCs>:8080
param([int]$Port = 8080)
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$types = @{ '.html'='text/html; charset=utf-8'; '.json'='application/manifest+json'; '.png'='image/png'; '.ico'='image/x-icon' }
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
# Port evtl. noch belegt (z. B. alte Instanz) -> warten statt ohne Listener weiterzulaufen
while ($true) { try { $listener.Start(); break } catch { Start-Sleep -Seconds 5 } }
while ($true) {
  $client = $listener.AcceptTcpClient()
  try {
    $client.ReceiveTimeout = 1000   # leere Vorab-Verbindungen (Browser-Preconnect) blockieren sonst den Server
    $stream = $client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream)
    $line = $reader.ReadLine()
    while ($true) { $h = $reader.ReadLine(); if ($h -eq $null -or $h -eq '') { break } }
    $path = (($line -split ' ')[1] -split '\?')[0]
    $name = [System.IO.Path]::GetFileName([Uri]::UnescapeDataString($path))
    if ([string]::IsNullOrEmpty($name)) { $name = 'raumsteuerung.html' }
    $file = Join-Path $root $name
    $ext = [System.IO.Path]::GetExtension($name).ToLower()
    if ((Test-Path -LiteralPath $file -PathType Leaf) -and $types.ContainsKey($ext) -and ($ext -ne '.json' -or $name -eq 'manifest.json')) {
      $body = [System.IO.File]::ReadAllBytes($file); $status = '200 OK'; $ct = $types[$ext]
    } else {
      $body = [System.Text.Encoding]::UTF8.GetBytes('Nicht gefunden'); $status = '404 Not Found'; $ct = 'text/plain; charset=utf-8'
    }
    $head = "HTTP/1.1 $status`r`nContent-Type: $ct`r`nContent-Length: $($body.Length)`r`nCache-Control: no-cache`r`nConnection: close`r`n`r`n"
    $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
    $stream.Write($hb, 0, $hb.Length); $stream.Write($body, 0, $body.Length); $stream.Flush()
  } catch { } finally { $client.Close() }
}
