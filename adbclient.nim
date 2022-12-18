import osproc, strutils, streams, os, random

type
  Connection* = ref object
    devId: string

  MotionEvent* = enum
    Up
    Down
    Move
    Cancel

const adbtool = "/opt/android-sdk/platform-tools/adb"

proc listDevices(): seq[string] =
  let logcat = startProcess(adbtool, args = ["devices"])
  let so = logcat.outputStream
  var line = ""
  var i = 0
  while so.readLine(line):
    line = line.strip()
    if i > 0:
      var ln = line.split('\t')
      if ln.len > 0:
        if ln[0].len > 0:
            result.add(ln[0])
    inc i

proc newConnection*(deviceId: string): Connection =
  Connection(devId: deviceId)

proc newConnection*(): Connection =
  let devs = listDevices()
  if devs.len == 1:
    result = newConnection(devs[0])

proc cmd(c: Connection, cm: string, output: var string): int {.discardable.} =
  let (o, errC) = execCmdEx(adbtool & " -s " & c.devId & " " & cm)
  output = o
  result = errC

proc cmd(c: Connection, cm: string): int {.discardable.} =
  var o: string
  c.cmd(cm, o)

proc shell(c: Connection, cm: string, output: var string): int {.discardable.} =
  c.cmd("shell " & cm, output)

proc shell*(c: Connection, cm: string): int {.discardable.} =
  var o: string
  c.shell(cm, o)

proc tap*(c: Connection, x, y: int) =
  c.shell("input tap " & $x & " " & $y)

proc motionevent*(c: Connection, e: MotionEvent, x, y: int) =
  let m = case e
          of Up: "UP"
          of Down: "DOWN"
          of Move: "Move"
          of Cancel: "CANCEL"
  c.shell("input motionevent " & m & " " & $x & " " & $y)

proc inputText*(c: Connection, t: string) =
  c.shell("input text " & quoteShell(t))

proc inputKeyEvent*(c: Connection, ev: int) =
  c.shell("input keyevent " & $ev)

proc inputSwipe*(c: Connection, x1, y1, x2, y2: int) =
  c.shell("input touchscreen swipe " & $x1 & " " & $y1 & " " & $x2 & " " & $y2)

proc launch*(c: Connection, pkgact: string) =
  c.shell("am start -n " & pkgact)

proc listPackages(c: Connection): seq[string] =
  var all = ""
  if c.shell("pm list packages -f", all) == 0:
    result = @[]
    for ln in all.splitLines():
      let line = ln.strip()
      if line.len > 0:
        result.add(line)

proc currentApp(c: Connection): string =
  discard c.shell("dumpsys window windows | grep mCurrentFocus", result)

proc getSizeWithPrefix(c: Connection, prefix: string): (int, int) =
  var szStr: string
  if c.cmd("shell wm size", szStr) == 0:
    for l in szStr.splitLines:
      if l.startsWith(prefix):
        let s = l[prefix.len .. ^1].split("x")
        return (parseInt(s[0]), parseInt(s[1]))

proc getPhysicalScreenSize*(c: Connection): (int, int) =
  getSizeWithPrefix(c, "Physical size: ")

proc getOverrideScreenSize*(c: Connection): (int, int) =
  getSizeWithPrefix(c, "Override size: ")

proc getScreenshot*(c: Connection): seq[byte] =
  let p = startProcess(adbtool, args = ["-s", c.devId, "exec-out", "screencap", "-p"], options = {})
  let s = p.outputStream
  var i = 0
  const delta = 1024 * 1024
  while true:
    result.setLen(result.len + delta)
    let r = s.readData(addr result[i], delta)
    i += r
    if r == 0:
      result.setLen(i)
      break
    elif r != delta:
      result.setLen(i)
  p.close()

proc getScreenshot*(c: Connection, localPath: string) =
  let s = c.getScreenshot()
  let f = newFileStream(localPath, fmWrite)
  f.writeData(addr s[0], s.len)
  f.close()
