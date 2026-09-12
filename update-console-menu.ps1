param([string]$Root)
if (-not $Root) { $Root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path } }
Set-Location -LiteralPath $Root
$utf8 = New-Object Text.UTF8Encoding($true)
function Write-Text([string]$Path, [string]$Content) { [IO.File]::WriteAllText($Path, $Content, $utf8); Write-Host "[OK] $Path" }

$c5 = [IO.File]::ReadAllText((Join-Path $Root 'src\ConsoleMenu.Wpf\Views\Ps5ShellView.xaml'))
$c5 = $c5 -replace '<UserControl\s+x:Class="ConsoleMenu\.Wpf\.Views\.Ps5ShellView"', '<views:ShellViewBase x:Class="ConsoleMenu.Wpf.Views.Ps5ShellView"'
$c5 = $c5 -replace 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"', 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:views="clr-namespace:ConsoleMenu.Wpf.Views"'
$c5 = $c5 -replace '</UserControl>', '</views:ShellViewBase>'
Write-Text (Join-Path $Root 'src\ConsoleMenu.Wpf\Views\Ps5ShellView.xaml') $c5

$c4 = [IO.File]::ReadAllText((Join-Path $Root 'src\ConsoleMenu.Wpf\Views\Ps4ShellView.xaml'))
$c4 = $c4 -replace '<UserControl\s+x:Class="ConsoleMenu\.Wpf\.Views\.Ps4ShellView"', '<views:ShellViewBase x:Class="ConsoleMenu.Wpf.Views.Ps4ShellView"'
$c4 = $c4 -replace 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"', 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:views="clr-namespace:ConsoleMenu.Wpf.Views"'
$c4 = $c4 -replace '</UserControl>', '</views:ShellViewBase>'
Write-Text (Join-Path $Root 'src\ConsoleMenu.Wpf\Views\Ps4ShellView.xaml') $c4

Write-Host ''
Write-Host '[i] Building...'
if (Get-Command dotnet -ErrorAction SilentlyContinue) { dotnet build (Join-Path $Root 'ConsoleMenu.sln') -v q --nologo } else { Write-Host '[i] dotnet not found' }