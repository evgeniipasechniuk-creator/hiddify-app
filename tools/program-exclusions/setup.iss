[Setup]
AppId=6L903538-42B1-4596-G479-BJ779F21A65D
AppName=Hiddify — Application exclusions
AppVersion=4.0.4
AppPublisher=Hiddify contributors; application exclusions fork
AppPublisherURL=https://github.com/hiddify/hiddify-app
DefaultDirName={autopf64}\Hiddify
UsePreviousAppDir=yes
DisableProgramGroupPage=yes
OutputDir=..\..\dist
OutputBaseFilename=Hiddify_Program_Exclusions_Setup_1
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
LicenseFile=..\..\LICENSE.md
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\PROGRAM_EXCLUSIONS_README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\LICENSE.md"; DestDir: "{app}"; DestName: "HIDDIFY_APP_LICENSE.md"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Hiddify"; Filename: "{app}\Hiddify.exe"
Name: "{autodesktop}\Hiddify"; Filename: "{app}\Hiddify.exe"

[Run]
Filename: "{app}\Hiddify.exe"; Description: "{cm:LaunchProgram,Hiddify}"; Flags: nowait postinstall skipifsilent runasoriginaluser

[Code]
procedure CopyBackupTree(SourceDir, TargetDir: String);
var
  Item: TFindRec;
  Source, Target: String;
begin
  if not DirExists(SourceDir) then Exit;
  if not ForceDirectories(TargetDir) then
    RaiseException('Cannot create the runtime backup directory.');
  if FindFirst(SourceDir + '\*', Item) then begin
    try
      repeat
        if (Item.Name <> '.') and (Item.Name <> '..') then begin
          Source := SourceDir + '\' + Item.Name;
          Target := TargetDir + '\' + Item.Name;
          if (Item.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
            CopyBackupTree(Source, Target)
          else if not FileCopy(Source, Target, False) then
            RaiseException('Cannot save the previous runtime: ' + Source);
        end;
      until not FindNext(Item);
    finally
      FindClose(Item);
    end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ExitCode: Integer;
  Target, Backup, Version: String;
  Item: TFindRec;
begin
  Result := '';
  Target := ExpandConstant('{app}');
  if FileExists(Target + '\Hiddify.exe') then begin
    if (not GetVersionNumbersString(Target + '\Hiddify.exe', Version)) or
       (Copy(Version, 1, 6) <> '4.0.4.') then begin
      Result := 'This update supports installed Hiddify 4.0.4 only. The installed version was not changed.';
      Exit;
    end;
    if DirExists(Target + '\hiddify_portable_data') then begin
      Result := 'This installer updates the installed application, not the portable edition. The portable data was not changed.';
      Exit;
    end;
    // The existing Windows tunnel service is stopped for this update; its
    // registration and settings are retained. Restarting loads the new DLL.
    Exec(ExpandConstant('{sys}\net.exe'), 'stop "HiddifyTunnelService"', '', SW_HIDE, ewWaitUntilTerminated, ExitCode);
    Backup := Target + '\application-exclusions-backup\' + GetDateTimeString('yyyymmdd-hhnnss', '-', ':');
    ForceDirectories(Backup);
    if FindFirst(Target + '\*', Item) then begin
      try
        repeat
          if (Item.Attributes and FILE_ATTRIBUTE_DIRECTORY) = 0 then
            if not FileCopy(Target + '\' + Item.Name, Backup + '\' + Item.Name, False) then begin
              Result := 'Close Hiddify using Exit (not the tray minimize button), then retry. The previous runtime could not be backed up.';
              Exit;
            end;
        until not FindNext(Item);
      finally
        FindClose(Item);
      end;
    end;
    try
      CopyBackupTree(Target + '\data', Backup + '\data');
    except
      Result := GetExceptionMessage;
    end;
  end;
  // Profiles and preferences under AppData are never deleted by this setup.
end;
