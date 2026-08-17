-- URL events: hammerspoon://<event> triggers the handler bound to <event>.
-- Test with: open "hammerspoon://hello"
hs.urlevent.bind("hello", function(eventName, params)
  hs.alert.show("hello")
end)

-- Run a sync script with a persistent progress alert; the callback closes it.
local function runSync(name, pr, progressMsg, doneMsg, onSuccess)
  local progress = hs.alert.show(progressMsg, 600)
  local script = os.getenv("HOME") .. "/.config/hammerspoon/" .. name .. ".sh"
  hs.task.new("/bin/bash", function(exitCode, stdOut, stdErr)
    hs.alert.closeSpecific(progress, 0)
    if exitCode == 0 then
      hs.alert.show(doneMsg)
      if onSuccess then onSuccess(stdOut) end
    else
      hs.alert.show(name .. " failed — see Hammerspoon console", 5)
      print(name .. " stdout:\n" .. stdOut)
      print(name .. " stderr:\n" .. stdErr)
    end
  end, { script, pr }):start()
end

-- hammerspoon://sync-to-gh?pr=<forgejo-pr-url>
-- Pushes the PR's branch to GitHub and opens a matching PR there.
hs.urlevent.bind("sync-to-gh", function(eventName, params)
  if not params.pr then
    hs.alert.show("sync-to-gh: missing pr param")
    return
  end
  runSync("sync-to-gh", params.pr, "Syncing to GitHub…", "Synced to GitHub", function(stdOut)
    local url = stdOut:match("(https://github%.com/%S+)%s*$")
    if url then hs.urlevent.openURL(url) end
  end)
end)

-- hammerspoon://sync-from-gh?repo=<forgejo-repo-url>
-- Pushes the GitHub upstream's default branch back to forgejo.
hs.urlevent.bind("sync-from-gh", function(eventName, params)
  if not params.repo then
    hs.alert.show("sync-from-gh: missing repo param")
    return
  end
  runSync("sync-from-gh", params.repo, "Syncing from GitHub…", "Synced from GitHub")
end)
