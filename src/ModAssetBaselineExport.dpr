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
  Prog.Config in 'Prog.Config.pas',
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
    OutDir: string;
    StyleName: string;
  end;

function ParseOptions(out Options: TOptions): Boolean;
var
  i: Integer;
  p: string;
begin
  Options.OutDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'baseline_modassets';
  Options.StyleName := DEFAULT_STYLE;

  i := 1;
  while i <= ParamCount do begin
    p := ParamStr(i);
    if SameText(p, '--out') and (i < ParamCount) then begin
      Inc(i);
      Options.OutDir := ParamStr(i);
    end
    else if SameText(p, '--style') and (i < ParamCount) then begin
      Inc(i);
      Options.StyleName := ParamStr(i);
    end
    else if SameText(p, '--help') or SameText(p, '-h') then begin
      Writeln('ModAssetBaselineExport');
      Writeln('  --out <folder>   Output folder (default: .\baseline_modassets)');
      Writeln('  --style <name>   Style name to export (default: Orig)');
      Writeln('Examples:');
      Writeln('  ModAssetBaselineExport.exe');
      Writeln('  ModAssetBaselineExport.exe --style Orig --out C:\Temp\baseline');
      Exit(False);
    end;
    Inc(i);
  end;

  Options.OutDir := IncludeTrailingPathDelimiter(ExpandFileName(Options.OutDir));
  Result := True;
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
    graph.Load(0, -1);
    aStyle.LemmingAnimationSet.AnimationPalette := Copy(graph.Palette);
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
  cfg: TConfig;
  style: TStyle;
  uiDir: string;
  lemmingsDir: string;
begin
  Writeln('[1/6] Loading config');
  cfg.Load;

  Writeln('[2/6] Initializing constants');
  Consts.Init(cfg.PathToStyles, cfg.PathToMusic, cfg.PathToSounds, cfg.PathToReplay);
  try
    Writeln('[3/6] Selecting style: ' + Options.StyleName);
    Consts.SetStyleName(Options.StyleName);
    Writeln('[4/6] Initializing style factory');
    TStyleFactory.Init;
    try
      Writeln('[5/6] Creating style instance');
      style := TStyleFactory.CreateStyle(True);
      try
        if style = nil then
          raise Exception.Create('TStyleFactory.CreateStyle returned nil');

        uiDir := IncludeTrailingPathDelimiter(Options.OutDir + 'UI');
        lemmingsDir := IncludeTrailingPathDelimiter(Options.OutDir + 'Lemmings');
        ForceDirectories(uiDir);
        ForceDirectories(lemmingsDir);

        Writeln('[6/6] Exporting UI and lemming assets');
        Writeln('  output UI dir: ' + uiDir);
        Writeln('  output Lemmings dir: ' + lemmingsDir);
        SaveMenuBaseline(style, uiDir);
        SaveLoadingBaseline(uiDir);
        SaveLemmingBaselines(style, lemmingsDir);
        SaveInfoFile(Options, Options.OutDir);
      finally
        style.Free;
      end;
    finally
      TStyleFactory.Done;
    end;
  finally
    Consts.Done;
  end;
end;

var
  opts: TOptions;
begin
  try
    if not ParseOptions(opts) then
      Exit;

    if not InitializeLemmix then
      Halt(1);

    Writeln('Exporting baseline ModAssets...');
    Writeln('Style: ' + opts.StyleName);
    Writeln('Out:   ' + opts.OutDir);
    RunExport(opts);
    Writeln('Done.');
  except
    on E: Exception do begin
      Writeln('ERROR: ' + E.Message);
      Halt(1);
    end;
  end;
end.
