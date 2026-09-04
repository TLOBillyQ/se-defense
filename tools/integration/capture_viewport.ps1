# #30 桌面抓屏兜底：editor-cli screenshot game/editor 在本环境视窗恒全白（GPU 画面不走 PrintWindow），
# 改抓桌面合成（CopyFromScreen）再裁切编辑器视窗区。前提：编辑器窗口在桌面可见（不最小化、视窗区不被遮挡）。
# 用法：powershell -File capture_viewport.ps1 -Out <png> [-Rect "x,y,w,h"]（默认为本机 1920×1080 下的视窗区）
param([string]$Out, [string]$Rect = "818,165,1100,841")
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$r = $Rect.Split(",") | ForEach-Object { [int]$_ }
$bmp = New-Object System.Drawing.Bitmap $r[2], $r[3]
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r[0], $r[1], 0, 0, $bmp.Size)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output "saved $Out $($r[2])x$($r[3])"
