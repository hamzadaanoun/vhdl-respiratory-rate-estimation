$ErrorActionPreference="Stop"
$racine=Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $racine
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { throw "FFmpeg absent." }
$sortie=Join-Path $racine "Resultats_Images"
New-Item -ItemType Directory -Force -Path $sortie | Out-Null
$images=@("01_rgb_original.ppm","02_grayscale.pgm","03_box_blur.pgm","04_sobel.pgm","05_threshold.pgm","06_morphology.pgm")
foreach($f in $images) {
 if(-not (Test-Path $f)){ Write-Warning "Absente : $f. Executer simulation et quit -sim."; continue }
 $base=[IO.Path]::GetFileNameWithoutExtension($f)
 & ffmpeg -hide_banner -loglevel error -y -i $f -vf "scale=640:640:flags=neighbor" -frames:v 1 -update 1 (Join-Path $sortie ($base+".png"))
 if($LASTEXITCODE -ne 0) { Write-Warning "Conversion impossible : $f" }
}
# ROI visualisee en coordonnees physiques RGB, +3 pour OFFSET_X/Y de rgb_roi_extractor
if((Test-Path "07_roi_coordinates.csv") -and (Test-Path "video_rgb_515frames.raw")) {
 $roi=@(Import-Csv "07_roi_coordinates.csv" -Delimiter ";")
 foreach($n in @(0,128,257,386,514)) {
  if($n -ge $roi.Count){continue}
  $r=$roi[$n]
  if($r.found -notmatch '1'){continue}
  $x=[int]$r.xmin+3; $y=[int]$r.ymin+3
  $w=[int]$r.xmax-[int]$r.xmin+1; $h=[int]$r.ymax-[int]$r.ymin+1
  $dest=Join-Path $sortie ("07_roi_trame_{0:D3}.png" -f $n)
  & ffmpeg -hide_banner -loglevel error -y -f rawvideo -pixel_format rgb24 -video_size 64x64 -framerate 25 -i "video_rgb_515frames.raw" -vf "select=eq(n\,$n),drawbox=x=${x}:y=${y}:w=${w}:h=${h}:color=green:t=1,scale=640:640:flags=neighbor" -frames:v 1 -update 1 $dest
 }
}
Write-Host "Images : $sortie" -ForegroundColor Green
Start-Process $sortie
