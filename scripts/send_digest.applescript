-- send_digest.applescript
-- argv: toEmail, subjectLine, bodyText
on run argv
  set toEmail to item 1 of argv
  set subjectLine to item 2 of argv
  set bodyText to item 3 of argv

  tell application "Mail"
    set newMessage to make new outgoing message with properties {subject:subjectLine, content:bodyText & return & return, visible:false}
    tell newMessage
      make new to recipient at end of to recipients with properties {address:toEmail}
      send
    end tell
  end tell

  return "OK"
end run
