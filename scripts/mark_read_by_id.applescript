-- mark_read_by_id.applescript
-- argv: message_id
on run argv
  set targetId to item 1 of argv

  tell application "Mail"
    set hits to (messages of inbox whose message id is targetId)
    if (count of hits) = 0 then return "NOT_FOUND"

    repeat with m in hits
      set read status of m to true
    end repeat
  end tell

  return "OK"
end run
