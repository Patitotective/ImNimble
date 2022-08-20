import std/[streams, osproc]

type
  MsgKind* = enum
    Process, Line, ExitCode, Quit

  Message* = object
    command*: string
    case kind*: MsgKind
    of Process:
      process*: Process
    of Line:
      line*: string
    of ExitCode:
      exitCode*: int
    of Quit:
      discard

# Global vars :skull:
var toProcesses*, fromProcesses*: Channel[Message]
var processesThread*: Thread[void]

proc readProcesses*() {.thread.} = 
 while true:
  let msg = toProcesses.recv()
  case msg.kind
  of MsgKind.Process:
    var tmp: string
    while msg.process.running:
      if msg.process.outputStream.readLine(tmp):# or msg.process.errorStream.readLine(tmp):
        fromProcesses.send(Message(command: msg.command, kind: MsgKind.Line, line: tmp))

    msg.process.close()
    fromProcesses.send(Message(command: msg.command, kind: MsgKind.ExitCode, exitCode: msg.process.peekExitCode))
  of MsgKind.Quit:
    break
  else: discard

proc startProcesses*() = 
  toProcesses.open()
  fromProcesses.open()
  processesThread.createThread(readProcesses)

proc endProcesses*() = 
  toProcesses.send(Message(kind: MsgKind.Quit))
  processesThread.joinThread()

  toProcesses.close()
  fromProcesses.close()

