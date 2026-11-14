Unicode true
!include "FileFunc.nsh"
Name "Love: 2 Gathering"
OutFile "${OUTPUT}"
RequestExecutionLevel user
SilentInstall silent
AutoCloseWindow true
!ifdef ICON
Icon "${ICON}"
!endif
Section
  ${GetParameters} $0
  SetOutPath "$EXEDIR"
  Exec '"$EXEDIR\runtime\python\pythonw.exe" "$EXEDIR\launcher.py" $0'
  IfErrors 0 done
  MessageBox MB_ICONSTOP "The bundled Python runtime could not start. Reinstall Love: 2 Gathering."
  done:
SectionEnd
