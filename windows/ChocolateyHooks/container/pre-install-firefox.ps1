# Firefox's taskbar verb can display an unreachable error dialog in Server Core.
if ($env:ChocolateyPackageParameters -notmatch '(?i)(?:^|\s)/NoTaskbarShortcut(?:[:=]|\s|$)') {
    $env:ChocolateyPackageParameters = ($env:ChocolateyPackageParameters + ' /NoTaskbarShortcut').Trim()
}
