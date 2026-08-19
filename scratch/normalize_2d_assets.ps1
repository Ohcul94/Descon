# ─────────────────────────────────────────────────────────────
# NORMALIZADOR DE ASSETS 2D (Descon)
# Redimensiona cualquier imagen 2D > 1024px a max 1024px
# (preservando proporción) para que renderice bien en
# AdminDash (browser) y en el juego (GL Compatibility).
#
# NO toca texturas de materiales 3D (*_basecolor/_normal/_rm)
# porque van embebidas en los .glb y funcionan.
#
# Uso:  powershell -ExecutionPolicy Bypass -File normalize_2d_assets.ps1
# ─────────────────────────────────────────────────────────────

Add-Type -AssemblyName System.Drawing

$assetsRoot = "E:\Descon\descon\assets"
$maxDim = 1024

# Patrones de texturas de materiales 3D que NO se tocan
$materialPattern = '_(basecolor|normal|rm|albedo|emissive|roughness|metallic|ao|height|opacity|specular)(\.|_|$)'

$exts = @('*.png', '*.jpg', '*.jpeg')
$files = Get-ChildItem -Path $assetsRoot -Recurse -File -Include $exts
$changed = 0
$skipped3d = 0

foreach ($f in $files) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)

    # Saltar texturas de materiales 3D
    if ($baseName -match $materialPattern) {
        $skipped3d++
        continue
    }

    try {
        $img = [System.Drawing.Image]::FromFile($f.FullName)
    } catch {
        Write-Host "SKIP (no decodifica): $($f.FullName)" -ForegroundColor Yellow
        continue
    }

    $w = $img.Width
    $h = $img.Height
    $max = [Math]::Max($w, $h)

    if ($max -le $maxDim) {
        $img.Dispose()
        continue
    }

    # Calcular nuevo tamaño preservando proporción
    $scale = $maxDim / [double]$max
    $nw = [Math]::Max(1, [int][Math]::Round($w * $scale))
    $nh = [Math]::Max(1, [int][Math]::Round($h * $scale))

    $bmp = New-Object System.Drawing.Bitmap($nw, $nh)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.DrawImage($img, 0, 0, $nw, $nh)
    $g.Dispose()
    $img.Dispose()

    # Guardar con el mismo formato
    if ($f.Extension -eq '.png') {
        $bmp.Save($f.FullName, [System.Drawing.Imaging.ImageFormat]::Png)
    } else {
        $enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
        $eps = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $eps.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]92)
        $bmp.Save($f.FullName, $enc, $eps)
    }
    $bmp.Dispose()

    # Eliminar .import para que Godot reimporte la textura
    $importFile = $f.FullName + '.import'
    if (Test-Path -LiteralPath $importFile) {
        Remove-Item -LiteralPath $importFile -Force
    }

    $changed++
    Write-Host "RESIZADO: $($f.FullName)  $($w)x$($h) -> ${nw}x${nh}" -ForegroundColor Green
}

Write-Host ""
Write-Host "══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  RESIZADOS: $changed   (texturas 3D intactas: $skipped3d)" -ForegroundColor Cyan
Write-Host "  IMPORTANTE: Abrí el proyecto en Godot para que reimporte." -ForegroundColor Yellow
Write-Host "══════════════════════════════════════════════" -ForegroundColor Cyan