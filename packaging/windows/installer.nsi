Unicode true
!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "Sections.nsh"
Var DesktopArgument
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
  InitPluginsDir
  ; Run the replacement worker and its Python from a private temporary payload,
  ; never from executables that the transaction needs to replace or remove.
  SetOutPath "$PLUGINSDIR\payload"
  File /r "${PAYLOAD}\*.*"
  WriteUninstaller "$PLUGINSDIR\payload\Uninstall.exe"
  SetOutPath "$PLUGINSDIR\links"
  CreateShortcut "$PLUGINSDIR\links\application.lnk" "$INSTDIR\Love2Gathering.exe"
  CreateShortcut "$PLUGINSDIR\links\uninstall.lnk" "$INSTDIR\Uninstall.exe"
  CreateShortcut "$PLUGINSDIR\links\desktop.lnk" "$INSTDIR\Love2Gathering.exe"
  StrCpy $DesktopArgument ""
  ; Application is section 0, the optional Desktop section is section 1.
  SectionGetFlags 1 $0
  IntOp $0 $0 & ${SF_SELECTED}
  ${If} $0 != 0
    StrCpy $DesktopArgument "--desktop-shortcut"
  ${EndIf}
  ClearErrors
  ExecWait '$\"$PLUGINSDIR\payload\runtime\python\pythonw.exe$\" -B $\"$PLUGINSDIR\payload\install_support.py$\" install --prefix $\"$INSTDIR$\" --source $\"$PLUGINSDIR\payload$\" --links $\"$PLUGINSDIR\links$\" --version $\"${VERSION}$\" --result $\"$PLUGINSDIR\result.json$\" $DesktopArgument' $0
  IfErrors install_failed
  StrCmp $0 0 install_done
  install_failed:
    StrCpy $1 "Installation could not finish. The previous installation and registration were retained."
    FileOpen $2 "$PLUGINSDIR\result.txt" r
    IfErrors +3
    FileRead $2 $1
    FileClose $2
    IfSilent +2
    MessageBox MB_ICONSTOP "$1"
    SetErrorLevel 2
    Quit
  install_done:
SectionEnd

Section /o "Desktop shortcut" Desktop
  ; The application section stages this option in its transactional helper.
SectionEnd

Section "Uninstall"
  SetShellVarContext current
  InitPluginsDir
  SetOutPath "$PLUGINSDIR\support"
  File /oname=install_support.py "${PAYLOAD}\install_support.py"
  SetOutPath "$PLUGINSDIR\support\runtime\python"
  File /r "${PAYLOAD}\runtime\python\*.*"
  ClearErrors
  ExecWait '$\"$PLUGINSDIR\support\runtime\python\pythonw.exe$\" -B $\"$PLUGINSDIR\support\install_support.py$\" uninstall --prefix $\"$INSTDIR$\" --result $\"$PLUGINSDIR\result.json$\"' $0
  IfErrors uninstall_failed
  StrCmp $0 0 uninstall_done
  uninstall_failed:
    StrCpy $1 "Uninstallation could not finish. Close the installed application and try again. Registration was retained."
    FileOpen $2 "$PLUGINSDIR\result.txt" r
    IfErrors +3
    FileRead $2 $1
    FileClose $2
    IfSilent +2
    MessageBox MB_ICONSTOP "$1"
    SetErrorLevel 2
    Quit
  uninstall_done:
SectionEnd
