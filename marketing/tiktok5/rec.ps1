# Records the Studio play viewport off the screen at 60 fps (ddagrab), with this terminal minimised
# meanwhile so it does not cover Studio.  rec.ps1 <out.mp4|out.png> <seconds> [x y w h]
param([string]$out, [double]$seconds, [int]$x = 0, [int]$y = 0, [int]$w = 0, [int]$h = 0)
Add-Type @"
using System; using System.Runtime.InteropServices;
public class RecWin { [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c); }
"@
$term = [IntPtr]67720
[RecWin]::ShowWindow($term, 6) | Out-Null # minimise
$ws = New-Object -ComObject WScript.Shell
$null = $ws.AppActivate("Ragdoll Mayhem - Roblox Studio")
Start-Sleep -Milliseconds 600
$src = "ddagrab=output_idx=0:framerate=60:draw_mouse=0"
if ($w -gt 0) { $src += ":offset_x=${x}:offset_y=${y}:video_size=${w}x${h}" }
if ($out.EndsWith(".png")) {
    ffmpeg -v error -y -f lavfi -i "$src,hwdownload,format=bgra" -frames:v 1 $out
} else {
    # encoded on the GPU (AMD AMF), the CPU only converts the frames: the rest of it stays the game's
    ffmpeg -v error -y -f lavfi -i "$src,hwdownload,format=bgra,format=nv12" -t $seconds -c:v h264_amf -usage transcoding -quality speed -rc cqp -qp_i 16 -qp_p 18 $out
}
[RecWin]::ShowWindow($term, 9) | Out-Null # restore
