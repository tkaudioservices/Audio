-- Add to Working Folders — a tiny drag-&-drop app.
-- Created by tk Audio Services.
--
-- Drag any folder onto this app's icon to pin it to your Working Folders shelf
-- (~/Working Folders). Double-clicking the app just opens the shelf.
--
-- This file is the SOURCE. Turn it into a real .app with:
--     ./working-folders.sh build-app
-- (menu option 6), which runs `osacompile` for you.

on hubPath()
	return (POSIX path of (path to home folder)) & "Working Folders"
end hubPath

on ensureHub()
	set h to hubPath()
	do shell script "mkdir -p " & quoted form of h
	return h
end ensureHub

-- Double-clicked with nothing dropped: just open the shelf.
on run
	set h to ensureHub()
	do shell script "open " & quoted form of h
end run

-- Folders (or files) dropped onto the icon: pin each one as a Finder alias.
on open theItems
	set h to ensureHub()
	tell application "Finder"
		set hubFolder to (POSIX file h) as alias
		repeat with anItem in theItems
			try
				set tgt to anItem as alias
				set tgtName to name of tgt
				if not (exists item tgtName of hubFolder) then
					make new alias file at hubFolder to tgt
				end if
			end try
		end repeat
	end tell
	do shell script "open " & quoted form of h
end open
