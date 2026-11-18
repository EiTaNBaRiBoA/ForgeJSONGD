# Runs every ForgeJSONGD test.
#
# The tests are a Godot .NET project of their own, kept in tests/project (its .gdignore keeps a
# project that holds this whole repository from loading the test models). This script builds a
# working copy of it in a scratch folder, with this repository's addon at addons/ForgeJSONGD,
# builds the C# project, imports it and runs every test scene headless.
#
#   .\run_tests.ps1                      uses the Godot .NET console exe next to the projects folder
#   .\run_tests.ps1 -Godot "C:\path\Godot_v4.7.2-stable_mono_win64_console.exe"
#   .\run_tests.ps1 -WorkDir <folder>    where the working copy goes (default: a folder in TEMP)
#   .\run_tests.ps1 -SchemaSuite <dir>   also runs the official JSON Schema Test Suite: <dir> is validation/tests
#                                        of a copy of https://github.com/json-schema-org/JSON-Schema-Test-Suite
#
# Needs the .NET build of Godot and the .NET SDK. Exit code: 0 when every scene passes, 1 otherwise.
param(
	[string]$Godot = $env:GODOT_MONO,
	[string]$WorkDir = "",
	[string]$SchemaSuite = "",
	[int]$TimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"
$Repo = $PSScriptRoot

if (-not $Godot) {
	$Godot = Join-Path $Repo "..\..\Godot\Godot_v4.7.2-stable_mono_win64_console.exe"
	if (-not (Test-Path $Godot)) { $Godot = Join-Path $Repo "..\Godot\Godot_v4.7.2-stable_mono_win64_console.exe" }
}
if (-not (Test-Path $Godot)) {
	Write-Error "Godot .NET console exe not found: $Godot. Pass -Godot <path> or set GODOT_MONO."
}
$Godot = (Resolve-Path $Godot).Path
if (-not $WorkDir) { $WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) "ForgeJSONGD-tests" }

# 1. A fresh working copy: the test project, and this repository's addon inside it.
Write-Host "Preparing the test project in $WorkDir"
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
Get-ChildItem (Join-Path $Repo "tests/project") -Force | Where-Object { $_.Name -ne ".gdignore" } | ForEach-Object {
	Copy-Item $_.FullName (Join-Path $WorkDir $_.Name) -Recurse
}
$addonCopy = Join-Path $WorkDir "addons/ForgeJSONGD"
New-Item -ItemType Directory -Force $addonCopy | Out-Null
foreach ($part in @("addons", "docs", "README.md", "LICENSE")) {
	$from = Join-Path $Repo $part
	if (Test-Path $from) { Copy-Item $from (Join-Path $addonCopy $part) -Recurse }
}
Set-Location $WorkDir

$scenes = @(
	"Scenes/main.tscn",
	"EnumAndDictionary/enum.tscn",
	"Inheritence/test.tscn",
	"Typed Dictionary/Typed.tscn",
	"Tests/features.tscn",
	"Tests/regression.tscn",
	"Tests/behaviors.tscn",
	"Tests/behaviors_more.tscn",
	"Tests/docs_examples.tscn",
	"Tests/exactness.tscn",
	"Tests/dto.tscn",
	"Tests/options.tscn",
	"Tests/http.tscn",
	"Tests/robustness.tscn",
	"Tests/fidelity.tscn",
	"Tests/validation.tscn",
	"CSharp/csharp_test.tscn"
)
if ($SchemaSuite) {
	if (-not (Test-Path $SchemaSuite)) {
		Write-Error "JSON Schema Test Suite folder not found: $SchemaSuite"
	}
	$env:FORGE_SCHEMA_SUITE = (Resolve-Path $SchemaSuite).Path
	$scenes += "Tests/schema_suite.tscn"
}

# The name each scene prints in its summary line.
$expectedSummary = @{
	"Scenes/main.tscn" = "Main"
	"EnumAndDictionary/enum.tscn" = "Enum"
	"Inheritence/test.tscn" = "Inheritance"
	"Typed Dictionary/Typed.tscn" = "Typed"
	"Tests/features.tscn" = "Features"
	"Tests/regression.tscn" = "Regression"
	"Tests/behaviors.tscn" = "Behaviors"
	"Tests/behaviors_more.tscn" = "Behaviors (more)"
	"Tests/docs_examples.tscn" = "Docs examples"
	"Tests/exactness.tscn" = "Exactness"
	"Tests/dto.tscn" = "Dto"
	"Tests/options.tscn" = "Options"
	"Tests/http.tscn" = "Http"
	"Tests/robustness.tscn" = "Robustness"
	"Tests/fidelity.tscn" = "Fidelity"
	"Tests/validation.tscn" = "Validation"
	"Tests/schema_suite.tscn" = "SchemaSuite"
	"CSharp/csharp_test.tscn" = "CSharp"
}

# Runs Godot with a timeout and returns its output and exit code.
function Invoke-Godot([string[]]$Arguments) {
	$out = [System.IO.Path]::GetTempFileName()
	$err = [System.IO.Path]::GetTempFileName()
	$process = Start-Process -FilePath $Godot -ArgumentList $Arguments -NoNewWindow -PassThru `
		-RedirectStandardOutput $out -RedirectStandardError $err
	$null = $process.Handle # keeps the process handle, so Windows PowerShell 5.1 can read ExitCode too
	if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
		$process.Kill()
		$timedOut = $true
	}
	else {
		$timedOut = $false
		$process.WaitForExit() # needed after a timed wait, otherwise ExitCode can be unreliable
	}
	$text = (Get-Content $out -Raw) + (Get-Content $err -Raw)
	Remove-Item $out, $err -ErrorAction SilentlyContinue
	[pscustomobject]@{ Text = $text; ExitCode = $(if ($timedOut) { -1 } else { $process.ExitCode }); TimedOut = $timedOut }
}

# A leftover C# compiler server from an earlier build can block the next build. Compile in-process instead.
$env:UseSharedCompilation = "false"
$env:MSBUILDDISABLENODEREUSE = "1"

Write-Host "Building the C# project (editor build)..."
$build = Invoke-Godot @("--headless", "--editor", "--path", ".", "--build-solutions", "--quit")
if ($build.ExitCode -ne 0) {
	Write-Host $build.Text
	Write-Error "The C# build failed (exit $($build.ExitCode), timed out: $($build.TimedOut))."
}

Write-Host "Importing the project (registers the [GlobalClass] types)..."
$import = Invoke-Godot @("--headless", "--path", ".", "--import", "--quit")
if ($import.ExitCode -ne 0) {
	Write-Host $import.Text
	Write-Error "The import failed."
}

$results = @()
foreach ($scene in $scenes) {
	# The scene path is quoted because some folders contain spaces.
	$run = Invoke-Godot @("--headless", "--path", ".", "`"res://$scene`"", "--quit-after", "30")
	$lines = $run.Text -split "`r?`n"
	$pass = ($lines | Where-Object { $_ -match "^PASS:" }).Count
	$fail = ($lines | Where-Object { $_ -match "^FAIL:" }).Count
	$summary = $lines | Where-Object { $_ -match "^== .* ==$" } | Select-Object -First 1
	$expected = $expectedSummary[$scene]
	$scriptErrors = ($lines | Where-Object { $_ -match "SCRIPT ERROR" }).Count
	# The summary line must belong to the scene that was asked for (a scene that fails to load falls back to the main scene).
	$ok = (-not $run.TimedOut) -and $fail -eq 0 -and $summary -eq "== $expected`: OK =="
	$results += [pscustomobject]@{ Scene = $scene; Pass = $pass; Fail = $fail; ScriptErrors = $scriptErrors; Result = $(if ($ok) { "OK" } elseif ($run.TimedOut) { "TIMEOUT" } else { "FAILED" }) }
	if (-not $ok) {
		$lines | Where-Object { $_ -match "^FAIL:|SCRIPT ERROR" } | ForEach-Object { Write-Host "  $_" }
	}
}

Set-Location $Repo
$results | Format-Table -AutoSize
$total = ($results | Measure-Object -Property Pass -Sum).Sum
$failed = @($results | Where-Object { $_.Result -ne "OK" }).Count
Write-Host "Total checks passed: $total"
if ($failed -gt 0) {
	Write-Host "$failed scene(s) failed."
	exit 1
}
Write-Host "All scenes passed."
exit 0
