Option Explicit

If WScript.Arguments.Count < 1 Then WScript.Quit 87

Dim shell, command, index
Set shell = CreateObject("WScript.Shell")
command = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & WScript.Arguments(0) & """"

For index = 1 To WScript.Arguments.Count - 1
  command = command & " """ & WScript.Arguments(index) & """"
Next

WScript.Quit shell.Run(command, 0, True)
