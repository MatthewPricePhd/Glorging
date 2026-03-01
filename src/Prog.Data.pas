unit Prog.Data;

{$include lem_directives.inc}

interface

uses
  Winapi.Windows,
  System.Classes, System.SysUtils, System.Contnrs, System.Zip, System.Generics.Collections, System.IOUtils,
  Vcl.Graphics, Vcl.Imaging.PngImage,
  GR32,
  Base.Utils, Base.Types,
  Prog.Base;

type
  TDataType = (
    Asset,                 // some assets
    Cursor,                // game cursor
    Sound,                 // game sound
    Particles,             // exploding particles
    LemmingData,           // generic lemmings data style dependant
    LevelGraphics,         // specific graphics data or vgaspecdata or metadata binding levelgraphics style dependant
    LevelSpecialGraphics,  // special graphics (vgaspec)
    Level,                 // LVL only, style dependant
    Music,                 // game music, style dependant
    Language
 );

type
  // quite a complicated bussiness
  TData = class sealed
  strict private
    const CACHE_LIMIT = 80 * 1024 * 1024;
  // cached stuff
    class var fLoadRequests: Integer;
    class var fCacheHits: Integer;
    class var fTotalCacheSize: Integer;
    class var fCache: TObjectDictionary<string, TBytesStream>;
    class var fModName: string;
    class var fModAssetsEnabled: Boolean;
    class function GetModAssetsRoot: string; static;
    class function GetPathToModAssets: string; static;
  public
    class constructor Create;
    class destructor Destroy;

    class function CreateDataStream(const aStyleName, aFileName: string; aType: TDataType; preventCaching: Boolean = False; disk: Boolean = False): TBytesStream; static;
    class function CreatePointer(const aStyleName, aFileName: string; aType: TDataType; out aSize: Integer; preventCaching: Boolean = False; disk: Boolean = False): Pointer; static;
    class function CreateCursorBitmap(const aStyleName, aFileName: string; preventCaching: Boolean = False): TBitmap; static;
    class function CreateAssetBitmap(const aFileName: string; preventCaching: Boolean = False): TBitmap32; static;
    class function CreateAssetWicImage(const aFileName: string; preventCaching: Boolean = False): TWicImage; static;
    class function CreateAssetPngImage(const aFileName: string; preventCaching: Boolean = False): TPngImage; static;

    class function CreateLanguageStringList(const aFileName: string; preventCaching: Boolean = False): TStringList; static;
    class function GetAvailableModNames: TArray<string>; static;
    class procedure SetModName(const aModName: string); static;
    class procedure ClearCache; static;
    class property ModName: string read fModName;
    class property ModAssetsEnabled: Boolean read fModAssetsEnabled write fModAssetsEnabled;
    class property PathToModAssets: string read GetPathToModAssets;
  end;

implementation

function EnumerateModAssetsRoots: TArray<string>;
var
  list: TStringList;

  procedure AddIfExists(const aPath: string);
  var
    path: string;
  begin
    path := IncludeTrailingPathDelimiter(ExpandFileName(aPath));
    if TDirectory.Exists(path) then
      list.Add(path);
  end;

begin
  list := TStringList.Create;
  try
    list.CaseSensitive := False;
    list.Sorted := False;
    list.Duplicates := dupIgnore;

    AddIfExists(IncludeTrailingPathDelimiter(Consts.PathToData) + 'ModAssets\');
    AddIfExists(Consts.AppPath + '..\Data\ModAssets\');
    AddIfExists(Consts.AppPath + '..\..\Data\ModAssets\');
    AddIfExists(Consts.AppPath + '..\..\..\Data\ModAssets\');
    AddIfExists(Consts.AppPath + '..\src\Data\ModAssets\');
    AddIfExists(Consts.AppPath + '..\..\src\Data\ModAssets\');

    SetLength(Result, list.Count);
    for var i := 0 to list.Count - 1 do
      Result[i] := list[i];
  finally
    list.Free;
  end;
end;

{ TData }

class constructor TData.Create;
begin
  fCache := TObjectDictionary<string, TBytesStream>.Create([doOwnsValues]);
  fModName := string.Empty;
  fModAssetsEnabled := True;
end;

class destructor TData.Destroy;
begin
  fCache.Free;
  // we normally have a high hit rate, so caching is nice.
  // var s: string := fLoadRequests.ToString + ' / ' + fCacheHits.ToString;
  //MessageBox(0, PChar(s), 'requests/cachehits', 0);
end;

class procedure TData.ClearCache;
begin
  fCache.Clear;
  fLoadRequests := 0;
  fCacheHits := 0;
  fTotalCacheSize := 0;
end;

class function TData.GetModAssetsRoot: string;
var
  roots: TArray<string>;
begin
  if not fModAssetsEnabled then
    Exit(string.Empty);

  roots := EnumerateModAssetsRoots;
  if Length(roots) = 0 then
    Exit(string.Empty);

  // If a pack is selected, prefer the root that actually contains it.
  if not fModName.IsEmpty then
    for var root in roots do
      if TDirectory.Exists(root + 'Packs\' + fModName + '\') then
        Exit(root);

  Result := roots[0];
end;

class function TData.GetPathToModAssets: string;
var
  roots: TArray<string>;
  packPath: string;
begin
  Result := GetModAssetsRoot;
  if Result.IsEmpty then
    Exit;

  if fModName.IsEmpty then
    Exit;

  roots := EnumerateModAssetsRoots;
  for var root in roots do begin
    packPath := root + 'Packs\' + fModName + '\';
    if TDirectory.Exists(packPath) then
      Exit(packPath);
  end;
end;

class procedure TData.SetModName(const aModName: string);
var
  roots: TArray<string>;
  candidate: string;
begin
  candidate := aModName.Trim;
  if not candidate.IsEmpty then begin
    var found := False;
    roots := EnumerateModAssetsRoots;
    for var root in roots do begin
      if TDirectory.Exists(root + 'Packs\' + candidate + '\') then begin
        found := True;
        Break;
      end;
    end;
    if not found then
      candidate := string.Empty;
  end;

  if SameText(fModName, candidate) then
    Exit;

  fModName := candidate;
  ClearCache;
end;

class function TData.GetAvailableModNames: TArray<string>;
var
  packRoot: string;
  root: string;
  dirs: TArray<string>;
  roots: TArray<string>;
  list: TStringList;
begin
  roots := EnumerateModAssetsRoots;
  if Length(roots) = 0 then
    Exit(nil);

  list := TStringList.Create;
  try
    list.CaseSensitive := False;
    list.Sorted := True;
    list.Duplicates := dupIgnore;

    for root in roots do begin
      packRoot := root + 'Packs\';
      if not TDirectory.Exists(packRoot) then
        Continue;
      dirs := TDirectory.GetDirectories(packRoot);
      for var dir in dirs do begin
        var name := ExtractFileName(dir);
        if name.IsEmpty then
          Continue;
        list.Add(name);
      end;
    end;

    SetLength(Result, list.Count);
    for var i := 0 to list.Count - 1 do
      Result[i] := list[i];
  finally
    list.Free;
  end;
end;

class function TData.CreateDataStream(const aStyleName, aFileName: string; aType: TDataType; preventCaching: Boolean = False; disk: Boolean = False): TBytesStream;
{-------------------------------------------------------------------------------
  Dependent on the datatype, we load a bytesstream.
-------------------------------------------------------------------------------}
const
  method = 'CreateDataStream';
var
  forceReadFromDisk: Boolean;
  filenameHasPath: Boolean;
  RealName: string;
  cachedStream: TBytesStream;
  mapping: Boolean;
  mappedResnameGraphics: string;

    procedure LoadFromZipResource(const aResName: string);
    var
      res: TResourceStream;
      str: TBytesStream;
      zip: TZipFile;
      bytes: System.SysUtils.TBytes;
      internalname: string;
    begin
      internalname := ExtractFileName(RealName); // no pathinfo in zip
      res := TResourceStream.Create(HINSTANCE, aResName, RT_RCDATA);
      try
        str := TBytesStream.Create;
        zip := TZipFile.Create;
        try
          str.CopyFrom(res, res.Size);
          str.Position := 0;
          zip.Open(str, TZipMode.zmRead);
          if zip.IndexOf(internalname) < 0 then
            Throw('File not found in zip-resource: ' + internalname, method + '.LoadFromZipResource');
          zip.Read(internalname, bytes);
          // the stream copies the bytes
          Result := TBytesStream.Create(bytes); // 'global' result
        finally
          zip.Free;
          str.Free;
        end;
      finally
        res.Free;
      end;
    end;

    procedure LoadFromNormalResource(const aResName: string);
    var
      res: TResourceStream;
    begin
      res := TResourceStream.Create(HINSTANCE, aResName, RT_RCDATA);
      try
        Result := TBytesStream.Create; // 'global' result
        Result.CopyFrom(res, 0);
      finally
        res.Free;
      end;
    end;

    procedure LoadFromDisk;
    begin
      if not FileExists(RealName) then
        Exit;
      Result := TBytesStream.Create; // 'global' result
      Result.LoadFromFile(RealName);
    end;

begin
  Result := nil;

  mapping := False;
  mappedResnameGraphics := string.Empty;

  forceReadFromDisk :=
    disk
    or ((Consts.StyleDef = TStyleDef.User) and (aType in [TDataType.LemmingData, TDataType.LevelGraphics, TDataType.LevelSpecialGraphics, TDataType.Level, TDataType.Music]))
    or (aType = TDataType.Language);

  if forceReadFromDisk then
    filenameHasPath := not ExtractFilePath(aFilename).IsEmpty
  else
    filenameHasPath := False;

  if not aStyleName.IsEmpty then begin

    var info: Consts.TStyleInformation := Consts.FindStyleInfo(aStyleName);
    if not Assigned(info) then
      Throw('Style not found ' + aStylename, method);

    if (info.UserGraphicsMapping in [TLevelGraphicsMapping.Concat, TLevelGraphicsMapping.Ohno]) and (aType in [TDataType.LemmingData, TDataType.LevelGraphics]) then begin
      mapping := True;
      case info.UserGraphicsMapping of
        TLevelGraphicsMapping.Default :  mappedResnameGraphics := 'CUSTOM';
        TLevelGraphicsMapping.Orig    :  mappedResnameGraphics := 'ORIG';
        TLevelGraphicsMapping.Ohno    :  mappedResnameGraphics := 'OHNO';
        TLevelGraphicsMapping.Concat  : mappedResnameGraphics := 'CUSTOM';
      end;
    end;

    if (info.UserSpecialGraphicsMapping = TLevelSpecialGraphicsMapping.Orig) and (aType = TDataType.LevelSpecialGraphics) then begin
      mapping := True;
    end;

  end;

  RealName := aFilename;
  case aType of
    TDataType.Asset                 : RealName := Consts.PathToAssets + ExtractFileName(aFileName);
    TDataType.Cursor                : RealName := Consts.PathToCursors + ExtractFileName(aFileName);
    TDataType.LemmingData           : RealName := Consts.PathToLemmings[aStylename] + ExtractFileName(aFileName);
    TDataType.LevelGraphics         : RealName := Consts.PathToLemmings[aStylename] + ExtractFileName(aFileName);
    TDataType.LevelSpecialGraphics  : RealName := Consts.PathToLemmings[aStylename] + ExtractFileName(aFileName);
    TDataType.Level                 : RealName := Consts.PathToLemmings[aStylename] + ExtractFileName(aFileName);
    TDataType.Sound                 : RealName := Consts.PathToSounds + ExtractFileName(aFileName);
    TDataType.Music                 : RealName := Consts.PathToMusics[aStylename] + ExtractFileName(aFileName);
    TDataType.Particles             : RealName := Consts.PathToParticles + ExtractFileName(aFileName);
    TDataType.Language              : if not filenameHasPath then RealName := Consts.PathToLanguage + ExtractFileName(aFileName);
  else
    Throw('Unhandled resource data type (' + aFileName + ')', 'CreateData');
  end;

  Inc(fLoadRequests);
  if not preventCaching and fCache.TryGetValue(RealName, cachedStream) then begin
    Result := TBytesStream.Create;
    Result.CopyFrom(cachedStream, 0);
    Result.Position := 0;
    Inc(fCacheHits);
    Exit;
  end;

  case aType of
    TDataType.Asset:
        if not forceReadFromDisk
        then LoadFromZipResource(Consts.ResNameAssets)
        else LoadFromDisk;
    TDataType.Cursor:
        if not forceReadFromDisk
        then LoadFromZipResource(Consts.ResNameZippedCursors)
        else LoadFromDisk;
    TDataType.LemmingData:
        if mapping then LoadFromZipResource(Consts.ResNameCustom)
        else if not forceReadFromDisk
        then LoadFromZipResource(Consts.ResourceNameZippedLemmings[aStylename])
        else LoadFromDisk;
    TDataType.LevelGraphics:
        if mapping then LoadFromZipResource(mappedResnameGraphics)
        else if not forceReadFromDisk
        then LoadFromZipResource(Consts.ResourceNameZippedLemmings[aStylename])
        else LoadFromDisk;
    TDataType.LevelSpecialGraphics:
        if mapping then LoadFromZipResource(Consts.ResNameCustom)
        else if not forceReadFromDisk
        then LoadFromZipResource(Consts.ResourceNameZippedLemmings[aStylename])
        else LoadFromDisk;
    TDataType.Level:
        if not forceReadFromDisk
        then LoadFromZipResource(Consts.ResourceNameZippedLemmings[aStylename])
        else LoadFromDisk;
    TDataType.Sound:
      begin
        if not forceReadFromDisk
        then LoadFromZipResource(Consts.ResNameZippedSounds)
        else LoadFromDisk;
      end;
    TDataType.Music:
      begin
        if not forceReadFromDisk
        then LoadFromZipResource(Consts.ResourceNameZippedMusics[aStylename])
        else LoadFromDisk;
      end;
    TDataType.Particles:
      begin
        if not forceReadFromDisk
        then LoadFromNormalResource(Consts.ResNameParticles)
        else LoadFromDisk;
      end;
    TDataType.Language:
      begin
        if forceReadFromDisk then
          LoadFromDisk; // never resourced
      end;
  end;

  if Result = nil then
    Throw('Unassigned datastream for ' + aFileName + '(' + RealName + ')', method);

  // only cache if not getting insane
  if not preventCaching and Assigned(Result) and (fTotalCacheSize < CACHE_LIMIT) then begin
    Inc(fTotalCacheSize, Result.Size);
    cachedStream := TBytesStream.Create;
    cachedStream.CopyFrom(Result, 0);
    fCache.Add(RealName, cachedStream);
  end;

  if Assigned(Result) then
    Result.Position := 0;
end;

class function TData.CreatePointer(const aStyleName, aFileName: string; aType: TDataType; out aSize: Integer; preventCaching: Boolean = False; disk: Boolean = False): Pointer;
// used for sounds
var
  stream: TBytesStream;
begin
  aSize := 0;
  Result := nil;
  stream := nil;
  try
    stream := CreateDataStream(aStyleName, aFileName, aType, preventCaching, disk);
    if stream.Size = 0 then
      Exit;
    GetMem(Result, stream.Size);
    Move(stream.Memory^, Result^, stream.Size);
    aSize := stream.Size;
  finally
    stream.Free;
  end;
end;

class function TData.CreateCursorBitmap(const aStyleName, aFileName: string; preventCaching: Boolean = False): TBitmap;
begin
  Result := nil;
  var stream : TBytesStream := nil;
  try
    stream := CreateDataStream(aStyleName, aFileName, TDataType.Cursor, preventCaching);
    Result := TBitmap.Create;
    try
      Result.LoadFromStream(stream);
    except
      FreeAndNil(Result);
      raise;
    end;
  finally
    stream.Free;
  end;
end;

class function TData.CreateAssetBitmap(const aFileName: string; preventCaching: Boolean): TBitmap32;
begin
  Result := nil;
  var stream : TBytesStream := nil;
  try
    stream := CreateDataStream(string.Empty, aFileName, TDataType.Asset, preventCaching);
    Result := TBitmap32.Create;
    try
      Result.LoadFromStream(stream);
    except
      FreeAndNil(Result);
      raise;
    end;
  finally
    stream.Free;
  end;
end;

class function TData.CreateAssetWicImage(const aFileName: string; preventCaching: Boolean): TWicImage;
begin
  Result := nil;
  var stream : TBytesStream := nil;
  try
    stream := CreateDataStream(string.Empty, aFileName, TDataType.Asset, preventCaching);
    Result := TWicImage.Create;
    try
      Result.LoadFromStream(stream);
    except
      FreeAndNil(Result);
      raise;
    end;
  finally
    stream.Free;
  end;
end;

class function TData.CreateAssetPngImage(const aFileName: string; preventCaching: Boolean): TPngImage;
begin
  Result := nil;
  var stream : TBytesStream := nil;
  try
    stream := CreateDataStream(string.Empty, aFileName, TDataType.Asset, preventCaching);
    Result := TPngImage.Create;
    try
      Result.LoadFromStream(stream);
    except
      FreeAndNil(Result);
      raise;
    end;
  finally
    stream.Free;
  end;
end;

class function TData.CreateLanguageStringList(const aFileName: string; preventCaching: Boolean = False): TStringList;
// language is in a file and never as resource
begin
  Result := nil;
  var stream : TBytesStream := nil;
  try
    stream := CreateDataStream(string.Empty, aFileName, TDataType.Language, preventCaching, True);
    Result := TStringList.Create;
    try
      Result.LoadFromStream(stream);
    except
      FreeAndNil(Result);
      raise;
    end;
  finally
    stream.Free;
  end;
end;

end.
