program ModAssetPreviewLauncher;

{$setpeflags 1}

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.SysUtils,
  System.IOUtils;

function Quote(const S: string): string;
begin
  Result := '"' + S + '"';
end;

function FindScriptPath: string;
var
  exeDir: string;
  candidates: TArray<string>;
begin
  exeDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  candidates := [
    ExpandFileName(exeDir + '..\tools\ModAssetPreview.ps1'),
    ExpandFileName(exeDir + 'tools\ModAssetPreview.ps1'),
    ExpandFileName(exeDir + '..\..\tools\ModAssetPreview.ps1'),
    ExpandFileName(exeDir + '..\src\tools\ModAssetPreview.ps1')
  ];

  for var c in candidates do
    if TFile.Exists(c) then
      Exit(c);

  Result := string.Empty;
end;

function FindRepoRootFromScript(const scriptPath: string): string;
begin
  // script is expected at <repo>\tools\ModAssetPreview.ps1
  Result := ExtractFileDir(ExtractFileDir(scriptPath));
end;

var
  scriptPath: string;
  repoRoot: string;
  args: string;
  rc: HINST;
begin
  scriptPath := FindScriptPath;
  if scriptPath.IsEmpty then begin
    MessageBox(0, 'Could not find tools\ModAssetPreview.ps1 near this launcher.', 'Mod Asset Preview Launcher', MB_ICONERROR or MB_OK);
    Halt(1);
  end;

  repoRoot := FindRepoRootFromScript(scriptPath);
  args := '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File ' + Quote(scriptPath);

  rc := ShellExecute(0, 'open', PChar('powershell.exe'), PChar(args), PChar(repoRoot), SW_SHOWNORMAL);
  if rc <= 32 then begin
    MessageBox(0, 'Failed to start powershell.exe for ModAssetPreview.ps1', 'Mod Asset Preview Launcher', MB_ICONERROR or MB_OK);
    Halt(1);
  end;
end.
