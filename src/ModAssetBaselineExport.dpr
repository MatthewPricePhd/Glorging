program ModAssetBaselineExport;

{$APPTYPE CONSOLE}
{$setpeflags 1}

{$include lem_directives.inc}
{$include lem_resources.inc}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  GR32 in 'Graphics32\GR32.pas',
  Base.Utils in 'Base.Utils.pas',
  Base.Bitmaps in 'Base.Bitmaps.pas',
  Base.Types in 'Base.Types.pas',
  Dos.MainDat in 'Dos.MainDat.pas',
  Prog.Base in 'Prog.Base.pas',
  Styles.Base in 'Styles.Base.pas',
  Styles.Factory in 'Styles.Factory.pas',
  Styles.Dos in 'Styles.Dos.pas',
  Styles.User in 'Styles.User.pas',
  Prog.Data in 'Prog.Data.pas',
  Dos.Consts in 'Dos.Consts.pas',
  Dos.Compression in 'Dos.Compression.pas',
  Dos.Bitmaps in 'Dos.Bitmaps.pas',
  Dos.Structures in 'Dos.Structures.pas',
  Meta.Structures in 'Meta.Structures.pas',
  Level.Base in 'Level.Base.pas',
  Level.Hash in 'Level.Hash.pas',
  Level.Loader in 'Level.Loader.pas';

const
  DEFAULT_STYLE = 'Orig';
  DEFAULT_CANVAS_WIDTH = 640;
  DEFAULT_CANVAS_HEIGHT = 350;

type
  TOptions = record
    GameRoot: string;
    OutDir: string;
    StyleName: string;
    AllStyles: Boolean;
    InteractiveMode: Boolean;
  end;

function ParseOptions(out Options: TOptions): Boolean;
var
  i: Integer;
  p: string;
begin
  Options.GameRoot := string.Empty;
  Options.OutDir := string.Empty;
  Options.StyleName := DEFAULT_STYLE;
  Options.AllStyles := False;
  Options.InteractiveMode := ParamCount = 0;

  i := 1;
  while i <= ParamCount do begin
    p := ParamStr(i);
    if SameText(p, '--game') and (i < ParamCount) then begin
      Inc(i);
      Options.GameRoot := ParamStr(i);
    end
    else
    if SameText(p, '--out') and (i < ParamCount) then begin
      Inc(i);
      Options.OutDir := ParamStr(i);
    end
    else if SameText(p, '--style') and (i < ParamCount) then begin
      Inc(i);
      Options.StyleName := ParamStr(i);
    end
    else if SameText(p, '--all-styles') then begin
      Options.AllStyles := True;
    end
    else if SameText(p, '--help') or SameText(p, '-h') then begin
      Writeln('ModAssetBaselineExport');
      Writeln('  --game <folder>  Game install root (contains Data\Styles and Lemmix.exe)');
      Writeln('  --out <folder>   Output folder (default: <game>\Data\ModAssets\Baseline)');
      Writeln('  --style <name>   Style name to export (default: Orig)');
      Writeln('  --all-styles     Export all built-in styles (Orig, Ohno, H94, X91, X92)');
      Writeln('Examples:');
      Writeln('  ModAssetBaselineExport.exe');
      Writeln('  ModAssetBaselineExport.exe --game C:\Games\Glorging --style Orig');
      Writeln('  ModAssetBaselineExport.exe --game C:\Games\Glorging --all-styles');
      Exit(False);
    end;
    Inc(i);
  end;

  if not Options.GameRoot.IsEmpty then
    Options.GameRoot := IncludeTrailingPathDelimiter(ExpandFileName(Options.GameRoot));
  if not Options.OutDir.IsEmpty then
    Options.OutDir := IncludeTrailingPathDelimiter(ExpandFileName(Options.OutDir));
  Result := True;
end;

procedure PauseForExplorer;
begin
  Writeln;
  Writeln('Press Enter to close...');
  Readln;
end;

function IsGameRoot(const RootPath: string): Boolean;
var
  p: string;
begin
  p := IncludeTrailingPathDelimiter(ExpandFileName(RootPath));
  Result := TDirectory.Exists(p + 'Data\Styles');
end;

procedure AddUniquePath(list: TStringList; const path: string);
var
  p: string;
begin
  p := IncludeTrailingPathDelimiter(ExpandFileName(path));
  if not IsGameRoot(p) then
    Exit;
  if list.IndexOf(p) < 0 then
    list.Add(p);
end;

function DiscoverGameRoots: TArray<string>;
var
  list: TStringList;
  baseDir: string;
  scanRoots: array[0..5] of string;
begin
  list := TStringList.Create;
  try
    list.Sorted := True;
    list.Duplicates := dupIgnore;

    baseDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
    scanRoots[0] := baseDir;
    scanRoots[1] := IncludeTrailingPathDelimiter(ExpandFileName(baseDir + '..\'));
    scanRoots[2] := IncludeTrailingPathDelimiter(ExpandFileName(baseDir + '..\..\'));
    scanRoots[3] := IncludeTrailingPathDelimiter(ExpandFileName(baseDir + '..\..\..\'));
    scanRoots[4] := IncludeTrailingPathDelimiter(ExpandFileName(baseDir + 'src\'));
    scanRoots[5] := IncludeTrailingPathDelimiter(ExpandFileName(baseDir + '..\src\'));

    for var root in scanRoots do begin
      AddUniquePath(list, root);
      AddUniquePath(list, root + 'dist\Glorging-win32\');
      AddUniquePath(list, root + 'runtime\upstream-2.1.0\');
      try
        for var d in TDirectory.GetDirectories(root) do begin
          AddUniquePath(list, d);
          try
            for var d2 in TDirectory.GetDirectories(d) do
              AddUniquePath(list, d2);
          except
          end;
        end;
      except
      end;
    end;

    SetLength(Result, list.Count);
    for var i := 0 to list.Count - 1 do
      Result[i] := list[i];
  finally
    list.Free;
  end;
end;

procedure PromptOptions(var Options: TOptions);
var
  s: string;
  gameRoots: TArray<string>;
  idx: Integer;
begin
  Writeln('Interactive mode');
  gameRoots := DiscoverGameRoots;
  if Length(gameRoots) > 0 then begin
    Writeln('Detected game installs:');
    for var i := 0 to High(gameRoots) do
      Writeln(Format('  %d) %s', [i + 1, gameRoots[i]]));
    Write('Choose game [1-' + IntToStr(Length(gameRoots)) + ', default=1]: ');
    Readln(s);
    if not TryStrToInt(Trim(s), idx) then
      idx := 1;
    if (idx < 1) or (idx > Length(gameRoots)) then
      idx := 1;
    Options.GameRoot := gameRoots[idx - 1];
  end
  else begin
    repeat
      Write('No install auto-detected. Enter game install folder: ');
      Readln(s);
      Options.GameRoot := IncludeTrailingPathDelimiter(ExpandFileName(Trim(s)));
    until IsGameRoot(Options.GameRoot);
  end;

  Writeln('  1 = single style');
  Writeln('  2 = all built-in styles');
  Write('Choose mode [1/2, default=1]: ');
  Readln(s);
  if s.Trim = '2' then
    Options.AllStyles := True;

  if not Options.AllStyles then begin
    Writeln('Styles: Orig, Ohno, H94, X91, X92');
    Write('Choose style [default=Orig]: ');
    Readln(s);
    if not s.Trim.IsEmpty then
      Options.StyleName := s.Trim;
  end;

  if Options.OutDir.IsEmpty then
    Options.OutDir := IncludeTrailingPathDelimiter(Options.GameRoot + 'Data\ModAssets\Baseline');

  Write('Output folder [default=' + Options.OutDir + ']: ');
  Readln(s);
  if not s.Trim.IsEmpty then
    Options.OutDir := IncludeTrailingPathDelimiter(ExpandFileName(s.Trim));
end;

procedure SaveMenuBaseline(const aStyle: TStyle; const aUiDir: string);
var
  extractor: TMainDatExtractor;
  tile: TBitmap32;
  outBmp: TBitmap32;
  x, y: Integer;
begin
  if aStyle = nil then
    raise Exception.Create('SaveMenuBaseline: style is nil');
  Writeln('  - SaveMenuBaseline: start');
  extractor := TMainDatExtractor.Create;
  tile := TBitmap32.Create;
  outBmp := TBitmap32.Create;
  try
    extractor.FileName := aStyle.MainDatFileName;
    Writeln('    main.dat = ' + extractor.FileName);
    extractor.ExtractBrownBackGround(tile);
    Writeln(Format('    extracted tile size: %dx%d', [tile.Width, tile.Height]));

    outBmp.SetSize(DEFAULT_CANVAS_WIDTH, DEFAULT_CANVAS_HEIGHT);
    outBmp.Clear(clBlack32);
    y := 0;
    while y < outBmp.Height do begin
      x := 0;
      while x < outBmp.Width do begin
        tile.DrawTo(outBmp, x, y);
        Inc(x, tile.Width);
      end;
      Inc(y, tile.Height);
    end;

    outBmp.SaveToPng(aUiDir + 'menu_background.png', TPngMode.Opaque);
    Writeln('    wrote ' + aUiDir + 'menu_background.png');
  finally
    outBmp.Free;
    tile.Free;
    extractor.Free;
  end;
end;

procedure SaveLoadingBaseline(const aUiDir: string);
var
  outBmp: TBitmap32;
begin
  Writeln('  - SaveLoadingBaseline: start');
  outBmp := TBitmap32.Create;
  try
    outBmp.SetSize(DEFAULT_CANVAS_WIDTH, DEFAULT_CANVAS_HEIGHT);
    outBmp.Clear(clBlack32);
    // Built-in loading screen has no dedicated background bitmap; keep black baseline.
    outBmp.SaveToPng(aUiDir + 'loading_background.png', TPngMode.Opaque);
    Writeln('    wrote ' + aUiDir + 'loading_background.png');
  finally
    outBmp.Free;
  end;
end;

procedure SaveLemmingBaselines(const aStyle: TStyle; const aLemmingsDir: string);
var
  i: Integer;
  masks: array[0..5] of TBitmap32;
  graph: TGraphicSet;
begin
  if aStyle = nil then
    raise Exception.Create('SaveLemmingBaselines: style is nil');
  graph := TGraphicSet.Create(aStyle);
  try
    try
      graph.Load(0, -1);
      aStyle.LemmingAnimationSet.AnimationPalette := Copy(graph.Palette);
    except
      // Some styles do not provide ground0.dat. For exporter purposes,
      // fallback to the default DOS menu palette to keep export running.
      aStyle.LemmingAnimationSet.AnimationPalette := GetDosMainMenuPaletteColors32;
    end;
  finally
    graph.Free;
  end;

  Writeln('  - SaveLemmingBaselines: loading animation set');
  aStyle.LemmingAnimationSet.Load;
  Writeln(Format('    animation strips: %d', [aStyle.LemmingAnimationSet.LemmingBitmaps.Count]));

  for i := 0 to aStyle.LemmingAnimationSet.LemmingBitmaps.Count - 1 do begin
    if aStyle.LemmingAnimationSet.LemmingBitmaps[i] = nil then
      raise Exception.CreateFmt('Nil animation strip at index %d', [i]);
    aStyle.LemmingAnimationSet.LemmingBitmaps[i].SaveToPng(
      aLemmingsDir + Format('anim_%.2d.png', [i]),
      TPngMode.BlackIsTransparent
    );
  end;
  Writeln('    wrote animation strips');

  masks[0] := aStyle.LemmingAnimationSet.BashMasksBitmap;
  masks[1] := aStyle.LemmingAnimationSet.BashMasksRTLBitmap;
  masks[2] := aStyle.LemmingAnimationSet.MineMasksBitmap;
  masks[3] := aStyle.LemmingAnimationSet.MineMasksRTLBitmap;
  masks[4] := aStyle.LemmingAnimationSet.ExplosionMaskBitmap;
  masks[5] := aStyle.LemmingAnimationSet.CountDownDigitsBitmap;

  for i := 0 to High(masks) do begin
    if masks[i] = nil then
      raise Exception.CreateFmt('Nil mask strip at index %d', [i]);
    masks[i].SaveToPng(
      aLemmingsDir + Format('mask_%.2d.png', [i]),
      TPngMode.BlackIsTransparent
    );
  end;
  Writeln('    wrote mask strips');
end;

procedure SaveInfoFile(const Options: TOptions; const outDir: string);
var
  list: TStringList;
begin
  list := TStringList.Create;
  try
    list.Add('Baseline ModAssets export');
    list.Add('GameRoot=' + Options.GameRoot);
    list.Add('Style=' + Options.StyleName);
    list.Add('Generated=' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
    list.Add('');
    list.Add('This folder is intended for reference-side visual diff in tools/ModAssetPreview.ps1.');
    list.Add('menu_background.png is reconstructed from built-in MAIN.DAT brown background tiling.');
    list.Add('loading_background.png is a black baseline because the built-in loading screen has no dedicated image file.');
    list.SaveToFile(outDir + 'EXPORT_INFO.txt');
  finally
    list.Free;
  end;
end;

procedure RunExport(const Options: TOptions);
var
  style: TStyle;
  uiDir: string;
  lemmingsDir: string;
  styleOutDir: string;
  styleNames: TArray<string>;
  stylesPath: string;
  musicPath: string;
  soundsPath: string;
begin
  Writeln('[1/6] Resolving game paths');
  stylesPath := IncludeTrailingPathDelimiter(Options.GameRoot + 'Data\Styles');
  musicPath := IncludeTrailingPathDelimiter(Options.GameRoot + 'Data\Music');
  soundsPath := IncludeTrailingPathDelimiter(Options.GameRoot + 'Data\Sounds');

  if not TDirectory.Exists(stylesPath) then
    raise Exception.Create('Selected game folder does not contain Data\Styles: ' + Options.GameRoot);
  if not TDirectory.Exists(musicPath) then
    musicPath := string.Empty;
  if not TDirectory.Exists(soundsPath) then
    soundsPath := string.Empty;

  Writeln('[2/6] Initializing constants');
  Consts.Init(stylesPath, musicPath, soundsPath, string.Empty);
  try
    // Baseline export must ignore local mod overrides.
    TData.ModAssetsEnabled := False;
    TData.SetModName(string.Empty);

    if Options.AllStyles then
      styleNames := [TStyleDef.Orig.Name, TStyleDef.Ohno.Name, TStyleDef.H94.Name, TStyleDef.X91.Name, TStyleDef.X92.Name]
    else
      styleNames := [Options.StyleName];

    Writeln('[3/6] Initializing style factory');
    TStyleFactory.Init;
    try
      for var styleName in styleNames do begin
        Writeln('[4/6] Selecting style: ' + styleName);
        Consts.SetStyleName(styleName);
        Writeln('[5/6] Creating style instance');
        style := TStyleFactory.CreateStyle(True);
        try
          if style = nil then
            raise Exception.Create('TStyleFactory.CreateStyle returned nil');

          if Options.AllStyles then
            styleOutDir := IncludeTrailingPathDelimiter(Options.OutDir + styleName)
          else
            styleOutDir := Options.OutDir;

          uiDir := IncludeTrailingPathDelimiter(styleOutDir + 'UI');
          lemmingsDir := IncludeTrailingPathDelimiter(styleOutDir + 'Lemmings');
          ForceDirectories(uiDir);
          ForceDirectories(lemmingsDir);

          Writeln('[6/6] Exporting UI and lemming assets');
          Writeln('  output UI dir: ' + uiDir);
          Writeln('  output Lemmings dir: ' + lemmingsDir);
          SaveMenuBaseline(style, uiDir);
          SaveLoadingBaseline(uiDir);
          SaveLemmingBaselines(style, lemmingsDir);

          var infoOptions := Options;
          infoOptions.StyleName := styleName;
          SaveInfoFile(infoOptions, styleOutDir);
        finally
          style.Free;
        end;
      end;
    finally
      TStyleFactory.Done;
    end;
  finally
    TData.ModAssetsEnabled := True;
    Consts.Done;
  end;
end;

var
  opts: TOptions;
  autoRoots: TArray<string>;
begin
  opts.InteractiveMode := False;
  try
    if not ParseOptions(opts) then
      Exit;

    if opts.InteractiveMode then
      PromptOptions(opts);

    if opts.GameRoot.IsEmpty then begin
      autoRoots := DiscoverGameRoots;
      if Length(autoRoots) > 0 then
        opts.GameRoot := autoRoots[0];
    end;

    if opts.GameRoot.IsEmpty then
      raise Exception.Create('No game install detected. Run without args for interactive selection or pass --game <folder>.');

    if not IsGameRoot(opts.GameRoot) then
      raise Exception.Create('Invalid game install folder (Data\Styles missing): ' + opts.GameRoot);

    if opts.OutDir.IsEmpty then
      opts.OutDir := IncludeTrailingPathDelimiter(opts.GameRoot + 'Data\ModAssets\Baseline');

    if not InitializeLemmix then
      Halt(1);

    Writeln('Exporting baseline ModAssets...');
    Writeln('Game:  ' + opts.GameRoot);
    if opts.AllStyles then
      Writeln('Style: <all built-in styles>')
    else
      Writeln('Style: ' + opts.StyleName);
    Writeln('Out:   ' + opts.OutDir);
    RunExport(opts);
    Writeln('Done.');
    if opts.InteractiveMode then
      PauseForExplorer;
  except
    on E: Exception do begin
      Writeln('ERROR: ' + E.Message);
      if opts.InteractiveMode then
        PauseForExplorer;
      Halt(1);
    end;
  end;
end.
