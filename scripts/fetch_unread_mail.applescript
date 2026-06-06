-- fetch_unread_mail.applescript
-- argv: max_count
-- Reads the UNIFIED inbox, which already aggregates every Mail.app account
-- (school + personal + ...), ordered most-recent-first. Taking the top N
-- therefore represents all accounts fairly instead of draining one first.
-- Output: JSON array string of objects:
-- [{ "id":"...", "subject":"...", "sender":"...", "date":"YYYY-MM-DD HH:MM:SS", "body":"...", "account":"..." }, ...]

on run argv
  set maxCount to 10
  if (count of argv) ≥ 1 then
    set maxCount to (item 1 of argv) as integer
  end if

  set itemsJSON to ""

  tell application "Mail"
    set inboxMessages to (messages of inbox whose read status is false)
    set n to (count of inboxMessages)
    if n = 0 then
      return "[]"
    end if

    set takeN to maxCount
    if n < takeN then set takeN to n

    repeat with i from 1 to takeN
      set m to item i of inboxMessages
      set sid to my json_escape((message id of m) as string)
      set subj to my json_escape((subject of m) as string)
      set sndr to my json_escape((sender of m) as string)
      set d to (date received of m)
      set datestr to my date_to_ymdhms(d)
      set contentText to my json_escape((content of m) as string)

      -- Which account this message belongs to (best-effort)
      set acctName to ""
      try
        set acctName to my json_escape((name of account of mailbox of m) as string)
      end try

      set one to "{\"id\":\"" & sid & "\",\"subject\":\"" & subj & "\",\"sender\":\"" & sndr & "\",\"date\":\"" & datestr & "\",\"body\":\"" & contentText & "\",\"account\":\"" & acctName & "\"}"

      if itemsJSON = "" then
        set itemsJSON to one
      else
        set itemsJSON to itemsJSON & "," & one
      end if
    end repeat
  end tell

  return "[" & itemsJSON & "]"
end run

on json_escape(t)
  set t to my replace_text("\\", "\\\\", t)
  set t to my replace_text("\"", "\\\"", t)
  set t to my replace_text(return, "\\n", t)
  set t to my replace_text(linefeed, "\\n", t)
  return t
end json_escape

on replace_text(find, repl, t)
  set AppleScript's text item delimiters to find
  set parts to text items of t
  set AppleScript's text item delimiters to repl
  set t to parts as string
  set AppleScript's text item delimiters to ""
  return t
end replace_text

on date_to_ymdhms(d)
  set y to year of d as integer
  set mo to month of d as integer
  set dd to day of d as integer
  set hh to hours of d as integer
  set mm to minutes of d as integer
  set ss to seconds of d as integer

  return (y as string) & "-" & my pad2(mo) & "-" & my pad2(dd) & " " & my pad2(hh) & ":" & my pad2(mm) & ":" & my pad2(ss)
end date_to_ymdhms

on pad2(x)
  if x < 10 then
    return "0" & (x as string)
  else
    return x as string
  end if
end pad2
