-- create_event.applescript
-- argv: title, startDateStr, endDateStr, locationStr, notesStr
-- date string format recommended: "20 February 2026 15:00:00"

on run argv
  set t to item 1 of argv
  set startStr to item 2 of argv
  set endStr to item 3 of argv
  set loc to item 4 of argv
  set notesText to item 5 of argv

  set startDate to date startStr
  set endDate to date endStr

  tell application "Calendar"
    if not (exists calendar "AI Draft") then
      error "Calendar named 'AI Draft' not found. Please create it in Calendar.app first."
    end if

    tell calendar "AI Draft"
      make new event with properties {summary:t, start date:startDate, end date:endDate, location:loc, description:notesText}
    end tell
  end tell

  return "OK"
end run
