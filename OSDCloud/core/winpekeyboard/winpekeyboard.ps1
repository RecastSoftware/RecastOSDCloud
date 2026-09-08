if (Get-Command -Name 'osk.exe' -ErrorAction Ignore) {
    Start-Process -FilePath 'osk.exe' -WindowStyle Minimized
}
