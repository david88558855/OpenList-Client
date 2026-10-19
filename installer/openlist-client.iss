; OpenList Client · Windows 安装版（Inno Setup 6）
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#define MyAppName "OpenList Client"
#define MyAppExeName "openlist_client.exe"

[Setup]
AppId={{6E2B7A54-3B7C-4B9E-9D2A-2E2B4C1D9F10}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={autopf}\OpenList Client
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=OpenList-Client-{#MyAppVersion}-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent
