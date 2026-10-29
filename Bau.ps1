# VAWVAW - デスクトップに住むペット
# start_VAWVAW.vbs から起動します（このファイルを直接ダブルクリックしなくて大丈夫です）
#
# さわらずに置いておくと:
#   30分 … good! と出てマイクで歌う
#   50分 … LAST! と出て画面の下を走り回る
#   60分 … 仰向けに寝転がって眠る（Zzz）
# クリック・メニュー操作で時間はリセットされます。

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

$VERSION = '2026-10-29 k'
$script:dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:dataDir = Join-Path $env:APPDATA 'Bau'
if (-not (Test-Path $script:dataDir)) { New-Item -ItemType Directory -Path $script:dataDir | Out-Null }
$script:statePath = Join-Path $script:dataDir 'state.json'
$script:logPath = Join-Path $script:dataDir 'vawvaw.log'
function Log([string]$msg) { try { Add-Content -Path $script:logPath -Value ("{0} {1}" -f (Get-Date -Format s), $msg) -Encoding UTF8 } catch {} }
trap { Log "error: $_"; continue }
Log "launch $VERSION pid=$PID"

# ---- 前のVAWVAW（古い版も含む）が動いていたら終わらせて、こちらに入れ替える ----
try {
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*Bau.ps1*' } |
    ForEach-Object { Log "stop old pid=$($_.ProcessId)"; Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} catch { Log "stop old: $_" }
$script:mutex = New-Object System.Threading.Mutex($false, 'Local\BauDesktopPet')
$got = $false
try { $got = $script:mutex.WaitOne(5000) } catch { $got = $true }
if (-not $got) { Log 'another VAWVAW is still running; exit'; exit }

function Now-Ms { [DateTimeOffset]::Now.ToUnixTimeMilliseconds() }

# ---- 時間の設定（分） ----
$MIN = 60000
# テスト用：$TEST_MODE = $true だと 1分ごとに Good! → Last!!! → 寝る に切り替わります
$TEST_MODE = $false
if ($TEST_MODE) {
  $T_GOOD = 1 * $MIN; $T_LAST = 2 * $MIN; $T_SLEEP = 3 * $MIN
  $SING_FOR = 1 * $MIN; $RUN_FOR = 1 * $MIN
} else {
  $T_GOOD = 30 * $MIN; $T_LAST = 50 * $MIN; $T_SLEEP = 60 * $MIN
  $SING_FOR = 3 * $MIN; $RUN_FOR = $T_SLEEP - $T_LAST  # 走るのは寝る時間まで続ける
}

# ---- 大きさ（横幅） ----
$SIZES = @{ large = 180; medium = 140; small = 105 }

# ---- セリフ ----
# ※ 変数名を $SAY にすると吹き出しの部品(Say)と同じ名前になって壊れるので $LINES にしています
$LINES = @{
  hello     = @('やあ、VAWVAWだよ。', 'おかえり！', 'きょうもよろしくね。')
  pet       = @('行くぜぇ‼', 'ねぇもっと!', 'もっと踊れ', 'そんなもんかい')
  feed      = @('もぐもぐ…おいしい！', 'クッキーだ！', 'ごちそうさま！')
  full      = @('もうおなかいっぱい…')
  play      = @('わーい！', 'ぴょんぴょん！', 'たのしい！')
  tired     = @('ちょっとつかれた…ごはんほしいな')
  sleepy    = @('すやすや…', 'Zzz…')
  hungry    = @('おなかすいた…')
  wake      = @('はっ…起きてたよ！')
  idle      = @('まだまだだな', '騒げー!!', '馬刺したべた', '声だせー!!', 'そでれ帰れんのか？', '俺が来た!!')
  workStart = @('いっしょにがんばろ！', '集中タイム！となりで見てるね')
  workTick  = @('ふむふむ…', 'いい調子！', 'あとすこし！')
  workDone  = @('おつかれさま！えらい！', '25分がんばったね！お茶にしよ')
}
function Pick($list) { $list[(Get-Random -Maximum $list.Count)] }

# ---- 記録（なつき度・おなか・位置） ----
$MAX = 10
$HOUR = 3600000
$script:st = [ordered]@{ aff = 3; full = 7; fedAt = (Now-Ms); born = (Now-Ms); left = $null; top = $null; size = $SIZES.large }
try {
  if (Test-Path $script:statePath) {
    $o = Get-Content -Path $script:statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($k in @('aff', 'full', 'fedAt', 'born', 'left', 'top', 'size')) {
      if ($null -ne $o.$k) { $script:st[$k] = $o.$k }
    }
  }
} catch { Log "load: $_" }
if ([int]$script:st.size -gt $SIZES.large) { $script:st.size = $SIZES.large }
function Clamp($n) { [Math]::Max(0, [Math]::Min($MAX, [int]$n)) }
function Save-State {
  try {
    if ($script:win) { $script:st.left = $script:win.Left; $script:st.top = $script:win.Top }
    ($script:st | ConvertTo-Json) | Set-Content -Path $script:statePath -Encoding UTF8
  } catch { Log "save: $_" }
}
function Apply-Hunger {
  $lost = [Math]::Floor(((Now-Ms) - [double]$script:st.fedAt) / (2 * $HOUR))
  if ($lost -gt 0) {
    $script:st.full = Clamp ($script:st.full - $lost)
    $script:st.fedAt = [double]$script:st.fedAt + $lost * 2 * $HOUR
  }
}
Apply-Hunger
Log "start $VERSION good=$($T_GOOD/$MIN)min last=$($T_LAST/$MIN)min sleep=$($T_SLEEP/$MIN)min"

# ---- 見た目 ----
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="VAWVAW" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize" Width="180" Height="250">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="46"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <Grid x:Name="Bubble" Grid.Row="0" Visibility="Hidden" HorizontalAlignment="Center" VerticalAlignment="Bottom" Opacity="0.92">
      <Border Background="White" BorderBrush="#D5DCE2" BorderThickness="1" CornerRadius="9" Padding="7,2" Margin="0,0,0,5">
        <TextBlock x:Name="Say" FontFamily="Yu Gothic UI" FontSize="11" Foreground="#4A5660"
                   TextWrapping="Wrap" MaxWidth="170" TextAlignment="Center"/>
      </Border>
      <Path Data="M0,0 L5,6 L10,0 Z" Fill="White" HorizontalAlignment="Center" VerticalAlignment="Bottom"/>
      <Path Data="M0,0 L5,6 L10,0" Stroke="#D5DCE2" StrokeThickness="1" HorizontalAlignment="Center" VerticalAlignment="Bottom"/>
    </Grid>

    <Viewbox Grid.Row="1" Stretch="Uniform">
      <Canvas Width="300" Height="340" Background="{x:Null}">
        <Ellipse x:Name="Shadow" Canvas.Left="62" Canvas.Top="319" Width="176" Height="18" Fill="Black" Opacity="0.16" RenderTransformOrigin="0.5,0.5">
          <Ellipse.RenderTransform><ScaleTransform/></Ellipse.RenderTransform>
        </Ellipse>

        <Canvas x:Name="Body" Width="300" Height="340" RenderTransformOrigin="0.5,0.953">
          <Canvas.RenderTransform>
            <TransformGroup><ScaleTransform/><RotateTransform/><TranslateTransform/></TransformGroup>
          </Canvas.RenderTransform>
          <Image x:Name="Sprite" Canvas.Left="30" Canvas.Top="44" Width="240" Height="284"/>

          <Canvas x:Name="Lids">
            <Ellipse Canvas.Left="127.5" Canvas.Top="122" Width="18" Height="18" Fill="#F07C1C" RenderTransformOrigin="0.5,0">
              <Ellipse.RenderTransform><ScaleTransform ScaleY="0"/></Ellipse.RenderTransform>
            </Ellipse>
            <Ellipse Canvas.Left="157.2" Canvas.Top="122" Width="18" Height="18" Fill="#F07C1C" RenderTransformOrigin="0.5,0">
              <Ellipse.RenderTransform><ScaleTransform ScaleY="0"/></Ellipse.RenderTransform>
            </Ellipse>
          </Canvas>
          <Canvas x:Name="Closed" Visibility="Collapsed">
            <Ellipse Canvas.Left="127.5" Canvas.Top="122" Width="18" Height="18" Fill="#F07C1C"/>
            <Ellipse Canvas.Left="157.2" Canvas.Top="122" Width="18" Height="18" Fill="#F07C1C"/>
            <Path Data="M129.5,132 Q136.5,137 143.5,132 M159.2,132 Q166.2,137 173.2,132" Stroke="#4A2208" StrokeThickness="2" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
          </Canvas>
          <Canvas x:Name="Smile" Visibility="Collapsed">
            <Ellipse Canvas.Left="127.5" Canvas.Top="122" Width="18" Height="18" Fill="White"/>
            <Ellipse Canvas.Left="157.2" Canvas.Top="122" Width="18" Height="18" Fill="White"/>
            <Path Data="M130.5,134 Q136.5,125 142.5,134 M160.2,134 Q166.2,125 172.2,134" Stroke="#2A1A10" StrokeThickness="2.6" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
          </Canvas>
          <Canvas x:Name="Snack" Visibility="Collapsed">
            <Ellipse Canvas.Left="133" Canvas.Top="177" Width="34" Height="34" Fill="#C98A4B"/>
            <Ellipse Canvas.Left="141.4" Canvas.Top="186.4" Width="5.2" Height="5.2" Fill="#5A3416"/>
            <Ellipse Canvas.Left="153.4" Canvas.Top="193.4" Width="5.2" Height="5.2" Fill="#5A3416"/>
            <Ellipse Canvas.Left="146.8" Canvas.Top="199.8" Width="4.4" Height="4.4" Fill="#5A3416"/>
          </Canvas>
          <Canvas x:Name="Mic" Visibility="Collapsed">
            <Line X1="176" Y1="184" X2="200" Y2="246" Stroke="#2B2B2B" StrokeThickness="8" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
            <Ellipse Canvas.Left="183" Canvas.Top="215" Width="22" Height="22" Fill="#E8701A" Stroke="#C85A0E" StrokeThickness="1.5"/>
            <Ellipse Canvas.Left="156" Canvas.Top="158" Width="28" Height="28" Fill="#5C6670" Stroke="#2B2B2B" StrokeThickness="2"/>
            <Path Data="M160,168 L180,168 M159,175 L181,175 M163,161 L163,184 M170,159 L170,185 M177,161 L177,184" Stroke="#9AA4AE" StrokeThickness="1"/>
          </Canvas>
        </Canvas>

        <Canvas x:Name="Hearts" Visibility="Collapsed">
          <Canvas Canvas.Left="30" Canvas.Top="40"><Canvas.RenderTransform><TranslateTransform/></Canvas.RenderTransform>
            <Viewbox Width="50" Height="50"><Canvas Width="56" Height="56">
              <Canvas Canvas.Left="6" Canvas.Top="10">
                <Path Data="M20,36 C20,36 2,24 2,12 C2,5 7,1 12,1 C16,1 19,4 20,7 C21,4 24,1 28,1 C33,1 38,5 38,12 C38,24 20,36 20,36 Z" Fill="White" Stroke="White" StrokeThickness="9" StrokeLineJoin="Round"/>
                <Path Canvas.Left="3" Canvas.Top="3" Data="M20,36 C20,36 2,24 2,12 C2,5 7,1 12,1 C16,1 19,4 20,7 C21,4 24,1 28,1 C33,1 38,5 38,12 C38,24 20,36 20,36 Z" Fill="White" Stroke="White" StrokeThickness="9" StrokeLineJoin="Round"/>
                <Path Canvas.Left="3" Canvas.Top="3" Data="M20,36 C20,36 2,24 2,12 C2,5 7,1 12,1 C16,1 19,4 20,7 C21,4 24,1 28,1 C33,1 38,5 38,12 C38,24 20,36 20,36 Z" Fill="#1A1A1A"/>
                <Path Data="M20,36 C20,36 2,24 2,12 C2,5 7,1 12,1 C16,1 19,4 20,7 C21,4 24,1 28,1 C33,1 38,5 38,12 C38,24 20,36 20,36 Z" Fill="#FF8A1F" Stroke="#1A1A1A" StrokeThickness="3" StrokeLineJoin="Round"/>
                <Path Data="M35,9 C37,17 31,25 21,32 C27,24 32,18 33,9 Z" Fill="#E0600A"/>
                <Ellipse Canvas.Left="24.7" Canvas.Top="20.7" Width="2.6" Height="2.6" Fill="#C9520A"/>
                <Ellipse Canvas.Left="28.7" Canvas.Top="17.7" Width="2.6" Height="2.6" Fill="#C9520A"/>
                <Ellipse Canvas.Left="21.7" Canvas.Top="24.7" Width="2.6" Height="2.6" Fill="#C9520A"/>
                <Ellipse Canvas.Left="26" Canvas.Top="25" Width="2" Height="2" Fill="#C9520A"/>
                <Ellipse Canvas.Left="30" Canvas.Top="14" Width="2" Height="2" Fill="#C9520A"/>
                <Path Data="M8,14 C8,9 10,6 14,5.5" Stroke="White" StrokeThickness="3.2" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                <Ellipse Canvas.Left="6.6" Canvas.Top="16.8" Width="3.4" Height="3.4" Fill="White"/>
                <Path Data="M39,-1 L43,-5 M42,6 L48,5 M33,-3 L34,-8" Stroke="#1A1A1A" StrokeThickness="2.4" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                <Path Data="M39,-1 L43,-5 M42,6 L48,5 M33,-3 L34,-8" Stroke="#FFD24D" StrokeThickness="1" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
              </Canvas>
            </Canvas></Viewbox>
          </Canvas>
          <Canvas Canvas.Left="224" Canvas.Top="70"><Canvas.RenderTransform><TranslateTransform/></Canvas.RenderTransform>
            <Viewbox Width="42" Height="42"><Canvas Width="56" Height="56">
              <Canvas Canvas.Left="6" Canvas.Top="10">
                <Path Data="M20,36 C20,36 2,24 2,12 C2,5 7,1 12,1 C16,1 19,4 20,7 C21,4 24,1 28,1 C33,1 38,5 38,12 C38,24 20,36 20,36 Z" Fill="White" Stroke="White" StrokeThickness="9" StrokeLineJoin="Round"/>
                <Path Canvas.Left="3" Canvas.Top="3" Data="M20,36 C20,36 2,24 2,12 C2,5 7,1 12,1 C16,1 19,4 20,7 C21,4 24,1 28,1 C33,1 38,5 38,12 C38,24 20,36 20,36 Z" Fill="White" Stroke="White" StrokeThickness="9" StrokeLineJoin="Round"/>
                <Path Canvas.Left="3" Canvas.Top="3" Data="M20,36 C20,36 2,24 2,12 C2,5 7,1 12,1 C16,1 19,4 20,7 C21,4 24,1 28,1 C33,1 38,5 38,12 C38,24 20,36 20,36 Z" Fill="#1A1A1A"/>
                <Path Data="M20,36 C20,36 2,24 2,12 C2,5 7,1 12,1 C16,1 19,4 20,7 C21,4 24,1 28,1 C33,1 38,5 38,12 C38,24 20,36 20,36 Z" Fill="#FF8A1F" Stroke="#1A1A1A" StrokeThickness="3" StrokeLineJoin="Round"/>
                <Path Data="M35,9 C37,17 31,25 21,32 C27,24 32,18 33,9 Z" Fill="#E0600A"/>
                <Ellipse Canvas.Left="24.7" Canvas.Top="20.7" Width="2.6" Height="2.6" Fill="#C9520A"/>
                <Ellipse Canvas.Left="28.7" Canvas.Top="17.7" Width="2.6" Height="2.6" Fill="#C9520A"/>
                <Ellipse Canvas.Left="21.7" Canvas.Top="24.7" Width="2.6" Height="2.6" Fill="#C9520A"/>
                <Ellipse Canvas.Left="26" Canvas.Top="25" Width="2" Height="2" Fill="#C9520A"/>
                <Ellipse Canvas.Left="30" Canvas.Top="14" Width="2" Height="2" Fill="#C9520A"/>
                <Path Data="M8,14 C8,9 10,6 14,5.5" Stroke="White" StrokeThickness="3.2" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                <Ellipse Canvas.Left="6.6" Canvas.Top="16.8" Width="3.4" Height="3.4" Fill="White"/>
                <Path Data="M39,-1 L43,-5 M42,6 L48,5 M33,-3 L34,-8" Stroke="#1A1A1A" StrokeThickness="2.4" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                <Path Data="M39,-1 L43,-5 M42,6 L48,5 M33,-3 L34,-8" Stroke="#FFD24D" StrokeThickness="1" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
              </Canvas>
            </Canvas></Viewbox>
          </Canvas>
          <Canvas Canvas.Left="196" Canvas.Top="10"><Canvas.RenderTransform><TranslateTransform/></Canvas.RenderTransform>
            <Viewbox Width="36" Height="36"><Canvas Width="56" Height="56">
              <Canvas Canvas.Left="6" Canvas.Top="10">
                <Path Data="M20,36 C20,36 2,24 2,12 C2,5 7,1 12,1 C16,1 19,4 20,7 C21,4 24,1 28,1 C33,1 38,5 38,12 C38,24 20,36 20,36 Z" Fill="White" Stroke="White" StrokeThickness="9" StrokeLineJoin="Round"/>
                <Path Canvas.Left="3" Canvas.Top="3" Data="M20,36 C20,36 2,24 2,12 C2,5 7,1 12,1 C16,1 19,4 20,7 C21,4 24,1 28,1 C33,1 38,5 38,12 C38,24 20,36 20,36 Z" Fill="White" Stroke="White" StrokeThickness="9" StrokeLineJoin="Round"/>
                <Path Canvas.Left="3" Canvas.Top="3" Data="M20,36 C20,36 2,24 2,12 C2,5 7,1 12,1 C16,1 19,4 20,7 C21,4 24,1 28,1 C33,1 38,5 38,12 C38,24 20,36 20,36 Z" Fill="#1A1A1A"/>
                <Path Data="M20,36 C20,36 2,24 2,12 C2,5 7,1 12,1 C16,1 19,4 20,7 C21,4 24,1 28,1 C33,1 38,5 38,12 C38,24 20,36 20,36 Z" Fill="#FF8A1F" Stroke="#1A1A1A" StrokeThickness="3" StrokeLineJoin="Round"/>
                <Path Data="M35,9 C37,17 31,25 21,32 C27,24 32,18 33,9 Z" Fill="#E0600A"/>
                <Ellipse Canvas.Left="24.7" Canvas.Top="20.7" Width="2.6" Height="2.6" Fill="#C9520A"/>
                <Ellipse Canvas.Left="28.7" Canvas.Top="17.7" Width="2.6" Height="2.6" Fill="#C9520A"/>
                <Ellipse Canvas.Left="21.7" Canvas.Top="24.7" Width="2.6" Height="2.6" Fill="#C9520A"/>
                <Ellipse Canvas.Left="26" Canvas.Top="25" Width="2" Height="2" Fill="#C9520A"/>
                <Ellipse Canvas.Left="30" Canvas.Top="14" Width="2" Height="2" Fill="#C9520A"/>
                <Path Data="M8,14 C8,9 10,6 14,5.5" Stroke="White" StrokeThickness="3.2" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                <Ellipse Canvas.Left="6.6" Canvas.Top="16.8" Width="3.4" Height="3.4" Fill="White"/>
                <Path Data="M39,-1 L43,-5 M42,6 L48,5 M33,-3 L34,-8" Stroke="#1A1A1A" StrokeThickness="2.4" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                <Path Data="M39,-1 L43,-5 M42,6 L48,5 M33,-3 L34,-8" Stroke="#FFD24D" StrokeThickness="1" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
              </Canvas>
            </Canvas></Viewbox>
          </Canvas>
        </Canvas>
        <Canvas x:Name="Notes" Visibility="Collapsed">
          <TextBlock Canvas.Left="236" Canvas.Top="110" FontSize="32" FontWeight="Bold" Foreground="#6B7CFF" Text="&#x266A;"><TextBlock.RenderTransform><TranslateTransform/></TextBlock.RenderTransform></TextBlock>
          <TextBlock Canvas.Left="30" Canvas.Top="96" FontSize="28" FontWeight="Bold" Foreground="#FF7AA8" Text="&#x266B;"><TextBlock.RenderTransform><TranslateTransform/></TextBlock.RenderTransform></TextBlock>
          <TextBlock Canvas.Left="250" Canvas.Top="54" FontSize="24" FontWeight="Bold" Foreground="#3FB6A8" Text="&#x266A;"><TextBlock.RenderTransform><TranslateTransform/></TextBlock.RenderTransform></TextBlock>
        </Canvas>
        <Canvas x:Name="Zzz" Visibility="Collapsed">
          <Canvas.RenderTransform><TranslateTransform/></Canvas.RenderTransform>
          <TextBlock Canvas.Left="205" Canvas.Top="46" FontSize="26" FontWeight="Bold" Foreground="#8AA4FF" Text="z"><TextBlock.RenderTransform><TranslateTransform/></TextBlock.RenderTransform></TextBlock>
          <TextBlock Canvas.Left="225" Canvas.Top="30" FontSize="21" FontWeight="Bold" Foreground="#8AA4FF" Text="z"><TextBlock.RenderTransform><TranslateTransform/></TextBlock.RenderTransform></TextBlock>
          <TextBlock Canvas.Left="242" Canvas.Top="18" FontSize="16" FontWeight="Bold" Foreground="#8AA4FF" Text="z"><TextBlock.RenderTransform><TranslateTransform/></TextBlock.RenderTransform></TextBlock>
        </Canvas>
        <Canvas x:Name="Dots" Visibility="Collapsed">
          <Ellipse Canvas.Left="227" Canvas.Top="47" Width="10" Height="10" Fill="#FFB25C"/>
          <Ellipse Canvas.Left="245" Canvas.Top="47" Width="10" Height="10" Fill="#FFB25C"/>
          <Ellipse Canvas.Left="263" Canvas.Top="47" Width="10" Height="10" Fill="#FFB25C"/>
        </Canvas>

        <TextBlock x:Name="Badge" Canvas.Left="0" Canvas.Top="0" Width="300" TextAlignment="Center" FontFamily="Arial Black, Segoe UI Black, Segoe UI"
                   FontSize="44" FontWeight="Black" Foreground="#FF8A00" Visibility="Collapsed" RenderTransformOrigin="0.5,0.5">
          <TextBlock.Effect><DropShadowEffect Color="White" BlurRadius="6" ShadowDepth="0" Opacity="1"/></TextBlock.Effect>
          <TextBlock.RenderTransform><ScaleTransform/></TextBlock.RenderTransform>
        </TextBlock>
      </Canvas>
    </Viewbox>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$script:win = [Windows.Markup.XamlReader]::Load($reader)
$win = $script:win
foreach ($n in @('Bubble', 'Say', 'Shadow', 'Body', 'Sprite', 'Lids', 'Closed', 'Smile', 'Snack', 'Mic', 'Hearts', 'Notes', 'Zzz', 'Dots', 'Badge')) {
  Set-Variable -Scope Script -Name $n -Value $win.FindName($n)
}

$bmp = New-Object System.Windows.Media.Imaging.BitmapImage
$bmp.BeginInit()
$bmp.UriSource = New-Object System.Uri (Join-Path $script:dir 'bau.png')
$bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
$bmp.EndInit()
$script:Sprite.Source = $bmp
[System.Windows.Media.RenderOptions]::SetBitmapScalingMode($script:Sprite, [System.Windows.Media.BitmapScalingMode]::HighQuality)

$script:bodyScale = $script:Body.RenderTransform.Children[0]
$script:bodyRot = $script:Body.RenderTransform.Children[1]
$script:bodyMove = $script:Body.RenderTransform.Children[2]
$script:shadowScale = $script:Shadow.RenderTransform
$script:badgeScale = $script:Badge.RenderTransform

# ---- 大きさと位置 ----
function Set-Size([int]$w) {
  $script:st.size = $w
  $script:win.Width = $w
  $script:win.Height = 46 + [Math]::Round($w * 340 / 300)
  $script:Say.MaxWidth = [Math]::Max(90, $w - 8)
}
Set-Size ([int]$script:st.size)
$wa = [System.Windows.SystemParameters]::WorkArea
if ($null -ne $script:st.left -and $null -ne $script:st.top -and
    [double]$script:st.left -ge ($wa.Left - 50) -and [double]$script:st.left -le ($wa.Right - 50) -and
    [double]$script:st.top -ge ($wa.Top - 50) -and [double]$script:st.top -le ($wa.Bottom - 80)) {
  $win.Left = [double]$script:st.left; $win.Top = [double]$script:st.top
} else {
  $win.Left = $wa.Right - $win.Width - 24
  $win.Top = $wa.Bottom - $win.Height - 4
}

# ---- 気分 ----
# idle / working / happy / eating / playing / singing / running / lying
$script:mood = 'idle'
$script:backAt = 0
$script:bubbleUntil = 0
$script:badgeAt = 0
$script:lastTouch = Now-Ms
$script:stage = @{ good = $false; last = $false; sleep = $false }
$script:workEnd = 0
$script:hover = $false
$script:runDir = -1
$script:lastT = 0.0
$script:t0 = [Diagnostics.Stopwatch]::StartNew()

function Show-Say([string]$text, [int]$ms = 4000) {
  $script:Say.Text = $text
  $script:Bubble.Visibility = 'Visible'
  $script:bubbleUntil = (Now-Ms) + $ms
}
function Show-Badge([string]$text, [string]$color) {
  $script:Badge.Text = $text
  $script:Badge.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($color)
  $script:Badge.Visibility = 'Visible'
  $script:badgeAt = Now-Ms
}
function Set-Mood([string]$m) {
  $script:mood = $m
  $vis = { param($b) if ($b) { 'Visible' } else { 'Collapsed' } }
  # 目はいつも黒目のまま（まぶた・笑い目・閉じ目は使わない）
  $script:Lids.Visibility   = 'Collapsed'
  $script:Closed.Visibility = 'Collapsed'
  $script:Smile.Visibility  = 'Collapsed'
  $script:Hearts.Visibility = & $vis ($m -in @('happy', 'playing'))
  $script:Notes.Visibility  = & $vis ($m -eq 'singing')
  $script:Mic.Visibility    = & $vis ($m -eq 'singing')
  $script:Zzz.Visibility    = & $vis ($m -eq 'lying')
  $script:Dots.Visibility   = & $vis ($m -eq 'working')
  $script:Snack.Visibility  = & $vis ($m -eq 'eating')
  # 寝転がるときは Zzz を頭の上（左側）へ
  if ($m -eq 'lying') { $script:Zzz.RenderTransform.X = -170; $script:Zzz.RenderTransform.Y = 50 }
  else { $script:Zzz.RenderTransform.X = 0; $script:Zzz.RenderTransform.Y = 0 }
  $script:bodyMove.X = 0; $script:bodyMove.Y = 0; $script:bodyRot.Angle = 0
}
function Rest-Mood { if ($script:workEnd -gt 0) { 'working' } else { 'idle' } }
function Act([string]$m, [string]$words, [int]$ms = 0) {
  Set-Mood $m
  if ($words) { Show-Say $words }
  $script:backAt = if ($ms -gt 0) { (Now-Ms) + $ms } else { 0 }
}
# さわったら時間をリセット。寝ていたら起きる
function Touch {
  $script:lastTouch = Now-Ms
  $script:stage.good = $false; $script:stage.last = $false; $script:stage.sleep = $false
  if ($script:mood -in @('lying', 'singing', 'running')) {
    $wasLying = ($script:mood -eq 'lying')
    Set-Mood (Rest-Mood)
    $script:backAt = 0
    if ($wasLying) { Show-Say (Pick $LINES.wake) }
    Save-State
    return $true
  }
  return $false
}

function Do-Pet {
  [void](Touch)
  $script:st.aff = Clamp ($script:st.aff + 1); Save-State
  Act 'happy' (Pick $LINES.pet) 3500
}
function Do-Feed {
  [void](Touch)
  if ($script:st.full -ge $MAX) { Act (Rest-Mood) (Pick $LINES.full); return }
  $script:st.full = Clamp ($script:st.full + 3); $script:st.fedAt = Now-Ms; Save-State
  Act 'eating' (Pick $LINES.feed) 4000
}
function Do-Play {
  [void](Touch)
  if ($script:st.full -le 1) { Act 'idle' (Pick $LINES.tired); return }
  $script:st.aff = Clamp ($script:st.aff + 1); $script:st.full = Clamp ($script:st.full - 1); Save-State
  Act 'playing' (Pick $LINES.play) 4500
}
function Toggle-Work {
  [void](Touch)
  if ($script:workEnd -gt 0) {
    $script:workEnd = 0
    Act 'idle' 'またいつでも呼んでね'
  } else {
    $script:workEnd = (Now-Ms) + 25 * $MIN
    Act 'working' (Pick $LINES.workStart)
  }
}

# ---- 右クリックメニュー ----
$startupDir = [Environment]::GetFolderPath('Startup')
$startupLnk = Join-Path $startupDir 'VAWVAW.lnk'
function New-StartupLink {
  $sh = New-Object -ComObject WScript.Shell
  $lnk = $sh.CreateShortcut($startupLnk)
  $lnk.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
  $lnk.Arguments = '"' + (Join-Path $script:dir 'start_VAWVAW.vbs') + '"'
  $lnk.WorkingDirectory = $script:dir
  $lnk.Save()
}
# 旧名のスタートアップ登録があれば、新しい名前とこのフォルダに付け替える
try {
  $oldLnk = Join-Path $startupDir ([string][char]0x30D0 + [char]0x30A6 + '.lnk')
  if (Test-Path $oldLnk) { Remove-Item $oldLnk; New-StartupLink }
  elseif (Test-Path $startupLnk) { New-StartupLink }
} catch { Log "startup migrate: $_" }
function Add-Item($menu, [string]$label, [scriptblock]$onClick) {
  $mi = New-Object System.Windows.Controls.MenuItem
  $mi.Header = $label
  $mi.Add_Click($onClick)
  [void]$menu.Items.Add($mi)
  $mi
}
$menu = New-Object System.Windows.Controls.ContextMenu
$menu.FontFamily = 'Yu Gothic UI'
[void](Add-Item $menu 'なでる' { Do-Pet })
[void](Add-Item $menu 'ごはん' { Do-Feed })
[void](Add-Item $menu 'あそぶ' { Do-Play })
$script:workItem = Add-Item $menu 'いっしょに作業する（25分）' { Toggle-Work }
[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
$sizeMenu = New-Object System.Windows.Controls.MenuItem
$sizeMenu.Header = '大きさ'
[void](Add-Item $sizeMenu '大' { Set-Size $SIZES.large; Save-State })
[void](Add-Item $sizeMenu '中' { Set-Size $SIZES.medium; Save-State })
[void](Add-Item $sizeMenu '小' { Set-Size $SIZES.small; Save-State })
[void]$menu.Items.Add($sizeMenu)
$script:startItem = Add-Item $menu 'パソコン起動時に表示する' {
  try {
    if (Test-Path $startupLnk) {
      Remove-Item $startupLnk
      Show-Say '次からは自分で呼んでね'
    } else {
      New-StartupLink
      Show-Say 'パソコンをつけたら会いにくるね！'
    }
  } catch { Log "startup: $_"; Show-Say '設定できなかったみたい…' }
}
[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
[void](Add-Item $menu 'VAWVAWをしまう（終了）' { Save-State; $script:win.Close() })
$menu.Add_Opened({
  $script:workItem.Header = if ($script:workEnd -gt 0) { '作業をやめる' } else { 'いっしょに作業する（25分）' }
  $script:startItem.IsChecked = (Test-Path $startupLnk)
})
$win.ContextMenu = $menu

# ---- マウス：ドラッグで移動、クリックでなでる ----
# ---- ダブルクリックで再起動（時間もリセット） ----
function Restart-Pet {
  Log 'restart (double-click)'
  Save-State
  try {
    Start-Process -FilePath (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList ('"' + (Join-Path $script:dir 'start_VAWVAW.vbs') + '"')
  } catch { Log "restart: $_" }
}
$script:lastClickAt = 0
$win.Add_MouseLeftButtonDown({
  $x0 = $script:win.Left; $y0 = $script:win.Top
  try { $script:win.DragMove() } catch {}
  if ([Math]::Abs($script:win.Left - $x0) -lt 3 -and [Math]::Abs($script:win.Top - $y0) -lt 3) {
    # ドラッグ移動のせいで Windows のダブルクリック判定が効かないので、2回のクリックの間隔で判定する
    $nowClick = Now-Ms
    if (($nowClick - $script:lastClickAt) -le 500) { $script:lastClickAt = 0; Restart-Pet; return }
    $script:lastClickAt = $nowClick
    if (-not (Touch)) { Do-Pet }
  } else {
    [void](Touch)
    Save-State
  }
})
$win.Add_MouseEnter({ $script:hover = $true })
$win.Add_MouseLeave({ $script:hover = $false })
$win.Add_Closed({ Save-State })

# ---- 毎フレームの動き ----
function Float-Fx($canvas, [double]$t, [double]$period = 2.4) {
  $i = 0
  foreach ($c in $canvas.Children) {
    $d = $i * 0.7
    $u = ((($t - $d) % $period) + $period) % $period / $period
    $c.Opacity = if ($u -lt 0.2) { $u / 0.2 } else { 1 - ($u - 0.2) / 0.8 }
    $c.RenderTransform.Y = 10 - 44 * $u
    $i++
  }
}
$script:nextCheck = (Now-Ms) + $MIN  # 起動直後は独り言を出さない
$tick = {
  try {
    $t = $script:t0.Elapsed.TotalSeconds
    $dt = [Math]::Min(0.1, $t - $script:lastT); $script:lastT = $t
    $now = Now-Ms
    $TWO_PI = 2 * [Math]::PI
    $sx = 1.0; $sy = 1.0; $rot = 0.0; $tx = 0.0; $ty = 0.0; $sh = 1.0
    $m = $script:mood
    if ($script:hover -and $m -eq 'idle') { $m = 'squish' }
    switch ($m) {
      'idle'    { $p = (1 - [Math]::Cos($TWO_PI * $t / 3.2)) / 2; $sx = 1 + 0.025 * $p; $sy = 1 - 0.025 * $p }
      'squish'  { $p = (1 - [Math]::Cos($TWO_PI * $t / 0.5)) / 2; $sx = 1 + 0.07 * $p; $sy = 1 - 0.08 * $p }
      'working' { $rot = 2.5 * [Math]::Sin($TWO_PI * $t / 0.45) }
      'eating'  { $p = (1 - [Math]::Cos($TWO_PI * $t / 0.35)) / 2; $sx = 1 + 0.04 * $p; $sy = 1 - 0.05 * $p }
      'happy'   { $p = (1 - [Math]::Cos($TWO_PI * $t / 0.55)) / 2; $ty = -22 * $p; $sx = 1.03 - 0.05 * $p; $sy = 0.97 + 0.05 * $p; $sh = 1 - 0.25 * $p }
      'playing' { $s = [Math]::Sin($TWO_PI * $t / 1.1); $ty = -26 * [Math]::Abs($s); $rot = -8 * $s; $sh = 1 - 0.25 * [Math]::Abs($s) }
      'singing' { $rot = 7 * [Math]::Sin($TWO_PI * $t / 1.2); $ty = -5 * [Math]::Abs([Math]::Sin($TWO_PI * $t / 0.6)) }
      'running' {
        $s = [Math]::Abs([Math]::Sin($TWO_PI * $t / 0.7))
        $ty = -8 * $s; $sh = 1 - 0.12 * $s
        $rot = 4 * $script:runDir
        # 画面の下を左右に走る
        $w = [System.Windows.SystemParameters]::WorkArea
        $x = $script:win.Left + $script:runDir * 70 * $dt
        if ($x -le $w.Left) { $x = $w.Left; $script:runDir = 1 }
        if ($x -ge $w.Right - $script:win.Width) { $x = $w.Right - $script:win.Width; $script:runDir = -1 }
        $script:win.Left = $x
        $script:win.Top = $w.Bottom - $script:win.Height + 2
      }
      'lying'   {
        # 仰向けに寝転がる：横に倒して、おなかがゆっくり上下
        $p = (1 - [Math]::Cos($TWO_PI * $t / 4.5)) / 2
        $rot = -90; $tx = 138; $ty = -112; $sx = 1 + 0.035 * $p; $sh = 1.35
      }
    }
    $script:bodyScale.ScaleX = $sx; $script:bodyScale.ScaleY = $sy
    $script:bodyRot.Angle = $rot
    $script:bodyMove.X = $tx; $script:bodyMove.Y = $ty
    $script:shadowScale.ScaleX = $sh; $script:shadowScale.ScaleY = [Math]::Min(1, $sh)

    # まばたき
    $f = ($t % 4.2) / 4.2
    $lid = if ($f -ge 0.90 -and $f -lt 0.94) { ($f - 0.90) / 0.04 } elseif ($f -ge 0.94) { (1 - $f) / 0.06 } else { 0 }
    foreach ($e in $script:Lids.Children) { $e.RenderTransform.ScaleY = $lid }

    if ($script:Hearts.Visibility -eq 'Visible') { Float-Fx $script:Hearts $t }
    if ($script:Notes.Visibility -eq 'Visible') { Float-Fx $script:Notes $t 2.0 }
    if ($script:Zzz.Visibility -eq 'Visible') { Float-Fx $script:Zzz $t 3.0 }
    if ($script:Dots.Visibility -eq 'Visible') {
      $i = 0
      foreach ($c in $script:Dots.Children) { $c.Opacity = 0.25 + 0.75 * (1 - [Math]::Cos($TWO_PI * ($t - $i * 0.2) / 1.2)) / 2; $i++ }
    }
    if ($script:Snack.Visibility -eq 'Visible') { $script:Snack.Opacity = 1 - [Math]::Floor(($t % 1.6) / 0.4) * 0.25 }

    # good! / LAST! のバッジ：ポンと出て4秒で消える
    if ($script:badgeAt -gt 0) {
      $a = ($now - $script:badgeAt) / 1000.0
      if ($a -ge 4) { $script:badgeAt = 0; $script:Badge.Visibility = 'Collapsed' }
      else {
        $k = if ($a -lt 0.15) { $a / 0.15 * 1.2 } elseif ($a -lt 0.3) { 1.2 - ($a - 0.15) / 0.15 * 0.2 } else { 1 }
        $script:badgeScale.ScaleX = $k; $script:badgeScale.ScaleY = $k
        $script:Badge.Opacity = if ($a -gt 3.4) { (4 - $a) / 0.6 } else { 1 }
      }
    }

    if ($script:backAt -gt 0 -and $now -ge $script:backAt) {
      $script:backAt = 0
      $wasRunning = ($script:mood -eq 'running')
      Set-Mood (Rest-Mood)
      if ($wasRunning) { Save-State }
    }
    if ($script:bubbleUntil -gt 0 -and $now -ge $script:bubbleUntil) { $script:bubbleUntil = 0; $script:Bubble.Visibility = 'Hidden' }

    if ($script:workEnd -gt 0 -and $now -ge $script:workEnd) {
      $script:workEnd = 0
      $script:st.aff = Clamp ($script:st.aff + 1); Save-State
      Act 'happy' (Pick $LINES.workDone) 8000
    }

    # さわらずに経過した時間で、歌う → 走る → 寝る
    $idleFor = $now - $script:lastTouch
    if ($idleFor -ge $T_SLEEP -and -not $script:stage.sleep) {
      $script:stage.sleep = $true; $script:stage.good = $true; $script:stage.last = $true
      Log 'stage sleep'; Act 'lying' (Pick $LINES.sleepy)
    } elseif ($idleFor -ge $T_LAST -and -not $script:stage.last) {
      $script:stage.last = $true; $script:stage.good = $true
      Log 'stage last'; Show-Say 'Last!!!'
      $script:runDir = if ($script:win.Left -gt ([System.Windows.SystemParameters]::WorkArea.Width / 2)) { -1 } else { 1 }
      Act 'running' $null $RUN_FOR
    } elseif ($idleFor -ge $T_GOOD -and -not $script:stage.good) {
      $script:stage.good = $true
      Log 'stage good'; Show-Say 'Good!'
      Act 'singing' $null $SING_FOR
    }

    if ($now -ge $script:nextCheck) {
      $script:nextCheck = $now + $MIN
      Apply-Hunger
      if ($script:mood -eq 'working' -and (Get-Random -Maximum 6) -eq 0) {
        Show-Say ((Pick $LINES.workTick) + ' のこり' + [Math]::Ceiling(($script:workEnd - $now) / $MIN) + '分')
      } elseif ($script:mood -eq 'idle') {
        if ($script:st.full -le 2 -and (Get-Random -Maximum 4) -eq 0) { Show-Say (Pick $LINES.hungry) }
        elseif ((Get-Random -Maximum 15) -eq 0) { Show-Say (Pick $LINES.idle) 3000 }
      }
    }
  } catch { Log "tick: $_" }
}
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(33)
$timer.Add_Tick($tick)

Set-Mood 'idle'
$win.Add_Loaded({
  $timer.Start()
  Show-Say 'あげぽよー!!' 5000
})
Save-State
[void]$win.ShowDialog()
$timer.Stop()
$script:mutex.ReleaseMutex()
