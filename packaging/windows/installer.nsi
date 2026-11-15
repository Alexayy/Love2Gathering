Unicode true
!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
Name "Love: 2 Gathering"
OutFile "${OUTPUT}"
InstallDir "$LOCALAPPDATA\Programs\Love2Gathering"
InstallDirRegKey HKCU "Software\Love2Gathering" "InstallDir"
RequestExecutionLevel user
; Card metadata and app resources are already compressed. Per-file zlib keeps
; build/install CPU low and allows sections to extract without a solid scan.
SetCompressor zlib
BrandingText "Love: 2 Gathering"
!ifdef ICON
Icon "${ICON}"
UninstallIcon "${ICON}"
!endif
!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Function .onVerifyInstDir
  ${GetRoot} "$INSTDIR" $0
  ${If} "$INSTDIR" == "$0"
    Abort
  ${EndIf}
  ${If} "$INSTDIR" == "$WINDIR"
  ${OrIf} "$INSTDIR" == "$SYSDIR"
    Abort
  ${EndIf}
  IfFileExists "$INSTDIR\.love2gathering-owned" verify_owner
  FindFirst $0 $1 "$INSTDIR\*"
  loop:
    StrCmp $1 "" valid_close
    StrCmp $1 "." next
    StrCmp $1 ".." next
    FindClose $0
    Abort
  next:
    FindNext $0 $1
    Goto loop
  valid_close:
    FindClose $0
    Goto valid
  verify_owner:
    ClearErrors
    FileOpen $0 "$INSTDIR\.love2gathering-owned" r
    IfErrors invalid_owner
    FileRead $0 $1
    FileClose $0
    StrLen $2 "io.github.Alexayy.Love2Gathering "
    StrCpy $1 $1 $2
    StrCmp $1 "io.github.Alexayy.Love2Gathering " valid
  invalid_owner:
    Abort
  valid:
FunctionEnd

Section "Application and bundled runtimes" Application
  SectionIn RO
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  File /r "${PAYLOAD}\*.*"
  FileOpen $0 "$INSTDIR\.love2gathering-owned" w
  FileWrite $0 "io.github.Alexayy.Love2Gathering ${VERSION}$\r$\n"
  FileClose $0
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\Love2Gathering"
  CreateShortcut "$SMPROGRAMS\Love2Gathering\Love2Gathering.lnk" "$INSTDIR\Love2Gathering.exe"
  CreateShortcut "$SMPROGRAMS\Love2Gathering\Uninstall.lnk" "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "Software\Love2Gathering" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Love2Gathering" "DisplayName" "Love: 2 Gathering"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Love2Gathering" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Love2Gathering" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Love2Gathering" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Love2Gathering" "DisplayIcon" "$INSTDIR\Love2Gathering.exe"
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Love2Gathering" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Love2Gathering" "NoRepair" 1
SectionEnd

Section /o "Desktop shortcut" Desktop
  CreateShortcut "$DESKTOP\Love2Gathering.lnk" "$INSTDIR\Love2Gathering.exe"
SectionEnd

Section "Uninstall"
  SetShellVarContext current
  IfFileExists "$INSTDIR\.love2gathering-owned" owned
    MessageBox MB_ICONSTOP "This folder is not a recognized Love2Gathering installation. No files were removed."
    Abort
  owned:
  FileOpen $0 "$INSTDIR\.love2gathering-owned" r
  FileRead $0 $1
  FileClose $0
  StrLen $2 "io.github.Alexayy.Love2Gathering "
  StrCpy $1 $1 $2
  ${If} $1 != "io.github.Alexayy.Love2Gathering "
    Abort
  ${EndIf}
  ; Generated exact file list: never recursively delete a user-selected directory.
  !include "${REMOVE_LIST}"
  Delete "$INSTDIR\.love2gathering-owned"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  ReadRegStr $0 HKCU "Software\Love2Gathering" "InstallDir"
  StrCmp $0 "$INSTDIR" 0 shortcuts_done
  Delete "$SMPROGRAMS\Love2Gathering\Love2Gathering.lnk"
  Delete "$SMPROGRAMS\Love2Gathering\Uninstall.lnk"
  RMDir "$SMPROGRAMS\Love2Gathering"
  Delete "$DESKTOP\Love2Gathering.lnk"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Love2Gathering"
  DeleteRegKey HKCU "Software\Love2Gathering"
  shortcuts_done:
SectionEnd
