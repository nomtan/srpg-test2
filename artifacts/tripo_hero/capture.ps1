$captureArgs = @(
    '--path', '.', '--resolution', '1280x720',
    '--log-file', 'C:/Users/nomur/Desktop/git/srpg-test2.worktrees/main/artifacts/tripo_hero/godot_capture.log',
    '--script', 'scripts/world_jrpg/verify_tripo_hero.gd', '--', '--capture'
)
$captureProcess = Start-Process -FilePath 'C:/Users/nomur/Desktop/godot/Godot_v4.6.1-stable_win64_console.exe' -ArgumentList $captureArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput 'artifacts/tripo_hero/capture_stdout.log' -RedirectStandardError 'artifacts/tripo_hero/capture_stderr.log'
$captureProcess.WaitForExit()
exit $captureProcess.ExitCode
