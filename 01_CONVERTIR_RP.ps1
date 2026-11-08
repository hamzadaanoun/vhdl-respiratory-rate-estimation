param([string]$Video = "rp.mp4")
$ErrorActionPreference = "Stop"
$racine = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $racine
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { throw "FFmpeg absent du PATH." }
if (-not (Test-Path $Video)) { throw "Video introuvable : $Video. Copier rp.mp4 dans le dossier." }
Write-Host "Conversion en 515 trames RGB24 de 64x64 a 25 fps..."
& ffmpeg -hide_banner -loglevel error -y -i $Video -vf "fps=25,scale=64:64:flags=bicubic" -frames:v 515 -f rawvideo -pix_fmt rgb24 "video_rgb_515frames.raw"
if ($LASTEXITCODE -ne 0) { throw "Erreur FFmpeg." }
$source = Join-Path $racine "video_rgb_515frames.raw"
$taille = (Get-Item $source).Length
if ($taille -ne (515*64*64*3)) { throw "Taille inattendue : $taille octets; attendu 6328320. Video trop courte ?" }
$sortie = Join-Path $racine "video_rgb_515frames.txt"
$hex = @(0..255 | ForEach-Object { $_.ToString("X2") })
$entree = [System.IO.File]::OpenRead($source)
$writer = [System.IO.StreamWriter]::new($sortie,$false,[System.Text.Encoding]::ASCII)
try {
    $buffer = New-Object byte[] 3
    while (($n = $entree.Read($buffer,0,3)) -eq 3) {
        $writer.WriteLine($hex[$buffer[0]]+$hex[$buffer[1]]+$hex[$buffer[2]])
    }
    if ($n -ne 0) { throw "Octets RGB incomplets." }
} finally { $writer.Dispose(); $entree.Dispose() }
Write-Host "ENTREE PRETE : $sortie ; 2109440 pixels."
