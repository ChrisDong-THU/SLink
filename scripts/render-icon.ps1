[CmdletBinding()]
param([string]$Output)
$ErrorActionPreference='Stop'
# Run with Windows PowerShell -STA. Render the simple SVG geometry directly at
# each size; no external asset tools or runtime dependencies are needed.
Add-Type -AssemblyName PresentationCore,WindowsBase
$repo=Split-Path $PSScriptRoot
if(-not $Output){$Output=Join-Path $repo 'artifacts/icon'}
[xml]$source=Get-Content -LiteralPath (Join-Path $repo 'assets/app.svg') -Raw
$ns=[Xml.XmlNamespaceManager]::new($source.NameTable);$ns.AddNamespace('s','http://www.w3.org/2000/svg')
$tile=$source.SelectSingleNode('/s:svg/s:rect',$ns)
$mark=$source.SelectSingleNode('/s:svg/s:g',$ns)
$gradient=[Windows.Media.LinearGradientBrush]::new()
$gradient.StartPoint=[Windows.Point]::new(0,0);$gradient.EndPoint=[Windows.Point]::new(1,1)
foreach($stop in $source.SelectNodes('//s:stop',$ns)){$gradient.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.ColorConverter]::ConvertFromString($stop.GetAttribute('stop-color')),[double]$stop.offset))}
$gradient.Freeze()
$paths=@($mark.SelectNodes('s:path',$ns) | ForEach-Object {[Windows.Media.Geometry]::Parse($_.d)})
$null=New-Item -ItemType Directory -Path $Output -Force
function Render-Icon([int]$Size) {
    $visual=[Windows.Media.DrawingVisual]::new();$dc=$visual.RenderOpen()
    try {
        $dc.PushTransform([Windows.Media.ScaleTransform]::new($Size/256.0,$Size/256.0))
        $dc.DrawRoundedRectangle($gradient,$null,[Windows.Rect]::new([double]$tile.x,[double]$tile.y,[double]$tile.width,[double]$tile.height),[double]$tile.rx,[double]$tile.rx)
        # Small tray icons need a slightly heavier stroke than the desktop master.
        $weight=if($Size -le 24){21}else{[double]$mark.GetAttribute('stroke-width')}
        $pen=[Windows.Media.Pen]::new([Windows.Media.Brushes]::White,$weight)
        $pen.StartLineCap='Round';$pen.EndLineCap='Round';$pen.LineJoin='Round'
        foreach($path in $paths){$dc.DrawGeometry($null,$pen,$path)}
        $dc.Pop()
    } finally {$dc.Close()}
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($Size,$Size,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual);$bitmap.Freeze();return $bitmap
}
function Png-Bytes($Bitmap) {
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($Bitmap))
    $stream=[IO.MemoryStream]::new()
    try {$encoder.Save($stream);return ,$stream.ToArray()} finally {$stream.Dispose()}
}
$sizes=@(16,20,24,32,40,48,64,96,128,256)
$frames=@();foreach($size in $sizes){$bytes=Png-Bytes (Render-Icon $size);$frames+=,@{size=$size;bytes=$bytes};[IO.File]::WriteAllBytes((Join-Path $Output "app-$size.png"),$bytes)}
[IO.File]::WriteAllBytes((Join-Path $Output 'app-512.png'),(Png-Bytes (Render-Icon 512)))
[IO.File]::WriteAllBytes((Join-Path $repo 'assets/app.png'),(Png-Bytes (Render-Icon 512)))
$stream=[IO.MemoryStream]::new();$writer=[IO.BinaryWriter]::new($stream)
try {
    $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$frames.Count)
    $offset=6+16*$frames.Count
    foreach($frame in $frames) {
        $dimension=if($frame.size -eq 256){0}else{$frame.size}
        $writer.Write([byte]$dimension);$writer.Write([byte]$dimension);$writer.Write([byte]0);$writer.Write([byte]0)
        $writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$frame.bytes.Length);$writer.Write([uint32]$offset)
        $offset+=$frame.bytes.Length
    }
    foreach($frame in $frames){$writer.Write([byte[]]$frame.bytes)}
    $writer.Flush();[IO.File]::WriteAllBytes((Join-Path $repo 'assets/app.ico'),$stream.ToArray())
} finally {$writer.Dispose();$stream.Dispose()}
# Review the actual small frames on light and dark surfaces, without enlarging them.
$visual=[Windows.Media.DrawingVisual]::new();$dc=$visual.RenderOpen()
try {
    $dc.DrawRectangle([Windows.Media.BrushConverter]::new().ConvertFromString('#F5F7FA'),$null,[Windows.Rect]::new(0,0,720,380))
    $dc.DrawRectangle([Windows.Media.BrushConverter]::new().ConvertFromString('#18212F'),$null,[Windows.Rect]::new(360,0,360,380))
    for($column=0;$column -lt 2;$column++) {
        $dc.DrawImage((Render-Icon 224),[Windows.Rect]::new($column*360+68,28,224,224))
        $x=$column*360+32
        foreach($size in @(16,20,24,32,48,64)) {
            $dc.DrawImage((Render-Icon $size),[Windows.Rect]::new($x,302-$size/2,$size,$size));$x+=$size+18
        }
    }
} finally {$dc.Close()}
$preview=[Windows.Media.Imaging.RenderTargetBitmap]::new(720,380,96,96,[Windows.Media.PixelFormats]::Pbgra32);$preview.Render($visual)
[IO.File]::WriteAllBytes((Join-Path $Output 'icon-preview.png'),(Png-Bytes $preview))
Get-Item (Join-Path $repo 'assets/app.ico'),(Join-Path $Output 'app-512.png') | Select-Object FullName,Length
