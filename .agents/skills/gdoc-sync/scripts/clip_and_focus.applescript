-- Load a markdown file onto the Mac clipboard as plain text and bring the doc tab to the front.
-- Replace __MD_PATH__, __DOC_ID__, __TAB_ID__ before passing to mac-host run_applescript.
use framework "Foundation"
use framework "AppKit"
use scripting additions
set mdPath to "__MD_PATH__"
set docId to "__DOC_ID__"
set tabId to "__TAB_ID__"
set md to current application's NSString's stringWithContentsOfFile:mdPath encoding:(current application's NSUTF8StringEncoding) |error|:(missing value)
if md is missing value then return "error: cannot read " & mdPath
set pb to current application's NSPasteboard's generalPasteboard()
pb's clearContents()
pb's setString:md forType:(current application's NSPasteboardTypeString)
set target to "https://docs.google.com/document/d/" & docId & "/edit?tab=" & tabId
tell application "Google Chrome"
	set found to false
	repeat with w in windows
		set i to 0
		repeat with t in tabs of w
			set i to i + 1
			if (URL of t) contains docId then
				set active tab index of w to i
				set index of w to 1
				if (URL of t) does not contain ("tab=" & tabId) then set URL of t to target
				set found to true
				exit repeat
			end if
		end repeat
		if found then exit repeat
	end repeat
	if not found then open location target
	activate
end tell
return "clipboard chars: " & ((md's |length|()) as integer) & ", existing tab: " & found
