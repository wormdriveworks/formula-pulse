# TL-1 로컬 단일 명령 (주력 GUI 머신/Windows) — CLI는 반드시 _console.exe (CLAUDE.md)
$godot = "C:\SDKs\godot\Godot_v4.7.1-stable_win64_console.exe"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $root
& $godot --headless --path . --script tools/validators/run_validators.gd
exit $LASTEXITCODE
