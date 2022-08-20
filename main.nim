import std/[algorithm, strformat, sequtils, strutils, random, osproc, json, math, os]

import downit
import imstyle
import niprefs
import openurl
import tinydialogs
import nimgl/[opengl, glfw]
import nimgl/imgui, nimgl/imgui/[impl_opengl, impl_glfw]

import src/[prefsmodal, processes, utils, icons]
when defined(release):
  from resourcesdata import resources

const configPath = "config.toml"

proc getData(path: string): string = 
  when defined(release):
    resources[path]
  else:
    readFile(path)

proc getData(node: TomlValueRef): string = 
  node.getString().getData()

proc getCacheDir(app: App): string = 
  getCacheDir(app.config["name"].getString())

proc drawAboutModal(app: App) = 
  var center: ImVec2
  getCenterNonUDT(center.addr, igGetMainViewport())
  igSetNextWindowPos(center, Always, igVec2(0.5f, 0.5f))

  let unusedOpen = true # Passing this parameter creates a close button
  if igBeginPopupModal(cstring "About " & app.config["name"].getString(), unusedOpen.unsafeAddr, flags = makeFlags(ImGuiWindowFlags.NoResize)):
    # Display icon image
    var texture: GLuint
    var image = app.config["iconPath"].getData().readImageFromMemory()

    image.loadTextureFromData(texture)

    igImage(cast[ptr ImTextureID](texture), igVec2(64, 64)) # Or igVec2(image.width.float32, image.height.float32)
    if igIsItemHovered():
      igSetTooltip(cstring app.config["website"].getString() & " " & FA_ExternalLink)
      
      if igIsMouseClicked(ImGuiMouseButton.Left):
        app.config["website"].getString().openUrl()

    igSameLine()
    
    igPushTextWrapPos(250)
    igTextWrapped(app.config["comment"].getString().cstring)
    igPopTextWrapPos()

    igSpacing()

    # To make it not clickable
    igPushItemFlag(ImGuiItemFlags.Disabled, true)
    igSelectable("Credits", true, makeFlags(ImGuiSelectableFlags.DontClosePopups))
    igPopItemFlag()

    if igBeginChild("##credits", igVec2(0, 75)):
      for author in app.config["authors"]:
        let (name, url) = block: 
          let (name,  url) = author.getString().removeInside('<', '>')
          (name.strip(),  url.strip())

        if igSelectable(cstring name) and url.len > 0:
            url.openURL()
        if igIsItemHovered() and url.len > 0:
          igSetTooltip(cstring url & " " & FA_ExternalLink)
      
      igEndChild()

    igSpacing()

    igText(app.config["version"].getString().cstring)

    igEndPopup()

proc drawMainMenuBar(app: var App) =
  var openAbout, openPrefs = false

  if igBeginMainMenuBar():
    if igBeginMenu("File"):
      igMenuItem("Preferences " & FA_Cog, "Ctrl+P", openPrefs.addr)
      if igMenuItem("Quit " & FA_Times, "Ctrl+Q"):
        app.win.setWindowShouldClose(true)
      igEndMenu()

    if igBeginMenu("Edit"):
      if igMenuItem("Hello"):
        echo "Hello"

      igEndMenu()

    if igBeginMenu("About"):
      if igMenuItem("Website " & FA_ExternalLink):
        app.config["website"].getString().openURL()

      igMenuItem(cstring "About " & app.config["name"].getString(), shortcut = nil, p_selected = openAbout.addr)

      igEndMenu() 

    igEndMainMenuBar()

  # See https://github.com/ocornut/imgui/issues/331#issuecomment-751372071
  if openPrefs:
    igOpenPopup("Preferences")
  if openAbout:
    igOpenPopup(cstring "About " & app.config["name"].getString())

  # These modals will only get drawn when igOpenPopup(name) are called, respectly
  app.drawAboutModal()
  app.drawPrefsModal()

proc filterFeedBySearch(app: var App) = 
  app.searchFeed = app.taggedFeed

  if app.searchBuffer.len > 0:
    app.searchFeed = app.searchFeed.filterIt(app.searchBuffer.passFilter(it.name))
  
  app.feedSlice = clamp(app.feedSlice.a, 0, app.searchFeed.high)..clamp(app.feedSlice.b, 0, app.searchFeed.high)

proc filterFeedByTags(app: var App, tags = @["installed"] & app.pkgsTags) = 
  app.taggedFeed = app.feed

  # By tags/installed
  if app.tags.len > 0:
    for tag in app.tags:
      if tag in tags:
        app.taggedFeed = app.taggedFeed.filterIt(tag in it.tags)
      elif tag == "installed":
        app.taggedFeed = app.taggedFeed.filterIt(it.name in app.installedPkgs)
      else: raise newException(ValueError, &"Invalid tag {tag}")

  app.feedSlice = clamp(app.feedSlice.a, 0, app.taggedFeed.high)..clamp(app.feedSlice.b, 0, app.taggedFeed.high)

  app.filterFeedBySearch()

proc sortFeed(app: var App) = 
  # Sort feed
  case app.currentSort
  of 0: # Alpha asc
    app.feed = app.feed.sortedByIt(it.name)
  of 1: # Alpha desc
    app.feed = app.feed.sortedByIt(it.name)
    app.feed.reverse()
  else: raise newException(ValueError, &"Invalid sort value {app.currentSort}")

  app.filterFeedByTags()

proc addLog(app: var App, line: openArray[char]) = 
  app.log.addLine(line)
  if app.prefs["autoScroll"].getBool():
    app.scrollToBottom = true

proc checkProcess(app: var App) = 
  let (ok, msg) = fromProcesses.tryRecv()
  if not ok: return

  case msg.kind
    of MsgKind.Line:
      app.addLog(msg.line)
    of MsgKind.ExitCode:    
      app.addLog(&"Exited with {msg.exitCode} code")
      app.running = false
      if msg.exitCode > 0 and msg.command == &"{app.prefs[\"nimbleCmd\"].getString()} --version":
        app.nimbleNotInstalled = true
        notifyPopup("Nimble Not Installed", &"{app.prefs[\"nimbleCmd\"].getString()} does not work. Make sure to that {app.prefs[\"nimbleCmd\"].getString()} exists.", Info)
    else: discard

proc runCmd(app: var App, args: openArray[string], cmd = app.prefs["nimbleCmd"].getString()) = 
  if app.running:
    notifyPopup("Already Running Process", "A process is already running. Wait until it finishes to stat another.", Info)
    return

  let command = &"{cmd} {args.join(\" \")}"
  try:
    toProcesses.send(Message(command: command, kind: MsgKind.Process, process: startProcess(cmd, args = args, options = {poStdErrToStdOut, poUsePath})))
    app.addLog(&"$ {command}")
    app.running = true
  except OSError:
    app.addLog(&"$ {command}")
    app.log.add("Error: ")
    app.addLog(getCurrentExceptionMsg().lastLine)

proc installPkg(app: var App, pkg: string) = 
  app.runCmd(["install", pkg, "-y"])

proc removePkg(app: var App, pkg: string) = 
  app.runCmd(["remove", pkg, "-y"])

proc drawTags(app: var App, tags: seq[string], addBtnRight = false): bool {.discardable.} = 
  let style = igGetStyle()
  let drawlist = igGetWindowDrawList()
  
  if not addBtnRight:
    if igButton(FA_Plus): igOpenPopup("addFilter")
    if tags.len > 0: igDummy(igVec2(style.itemSpacing.x, 0)); igSameLine()
  elif tags.len > 0:
    igSameLine(0, style.itemSpacing.x)

  for e, filter in app.tags.deepCopy():
    drawList.channelsSplit(2)

    drawList.channelsSetCurrent(1)
    igAlignTextToFramePadding()
    igText(cstring filter.capitalizeAscii())
    
    drawList.channelsSetCurrent(0)
    drawlist.addRectFilled(igGetItemRectMin() - style.framePadding, igGetItemRectMax() + style.framePadding, igGetColorU32(ImGuiCol.Tab))

    drawList.channelsMerge()

    igSameLine()
    igPushStyleVar(FrameRounding, 0f)
    igPushStyleColor(ImGuiCol.Button, igGetColorU32(ImGuiCol.Tab))
    igPushStyleColor(ImGuiCol.ButtonHovered, igGetColorU32(ImGuiCol.TabHovered))
    igPushStyleColor(ImGuiCol.ButtonActive, igGetColorU32(ImGuiCol.TabActive))

    if igButton(cstring &"{FA_Times}##{e}"):
      result = true
      app.tags.delete(app.tags.find(filter))

    igPopStyleColor(3)
    igPopStyleVar()

    let lastButton = igGetItemRectMax().x
    # Expected position if next button was on same line
    let nextButton = lastButton + 0.5 + 
      (if e < app.tags.high: igCalcFrameSize(app.tags[e + 1].capitalizeAscii()).x + style.itemSpacing.x + igCalcFrameSize(FA_Times).x + 
      (if addBtnRight: igCalcFrameSize(FA_Plus).x + style.itemSpacing.x else: 0) 
      else: 0)
    
    if e < app.tags.high:
      if nextButton < igGetWindowPos().x + igGetWindowContentRegionMax().x:
        igSameLine(0, style.itemSpacing.x * 2)
      else:
        igDummy(igVec2(style.itemSpacing.x, 0)); igSameLine()

  if addBtnRight:
    if tags.len > 0: igSameLine()
    if igButton(FA_Plus): igOpenPopup("addFilter")

  if igBeginPopup("addFilter"):
    igInputTextWithHint("##tagsFilter", "Search tags", cstring app.tagsBuffer, 100)

    if igBeginChild("##tagsList", size = igVec2(0, 300), flags = NoBackground):
      for e, tag in tags:
        if tag notin app.tags and app.tagsBuffer.passFilter(tag) and igMenuItem(cstring tag.capitalizeAscii()):
          result = true
          app.tags.add(tag)

    igEndChild()

    igEndPopup()

proc drawPkgsListHeader(app: var App) = 
  let style = igGetStyle()

  igSetNextItemWidth(igGetContentRegionAvail().x - (style.itemSpacing.x * 2) - igCalcFrameSize(FA_Sort).x - igCalcFrameSize(FA_Plus).x - style.framePadding.x)
  if igInputTextWithHint("##search", "Search packages", cstring app.searchBuffer, 100):
    app.filterFeedBySearch()

  igSameLine()

  if igButton(FA_Sort):
    igOpenPopup("sort")
  igSameLine()

  if app.drawTags(@["installed"] & app.pkgsTags):
    app.filterFeedByTags()

  if igBeginPopup("sort"):
    for e, ele in [FA_SortAlphaAsc, FA_SortAlphaDesc, "Newest", "Oldest"]:
      if igSelectable(cstring ele, e == app.currentSort):
        app.currentSort = e
        app.sortFeed()

    igEndPopup()

proc drawPkgsList(app: var App) = 
  let style = igGetStyle()

  if app.searchFeed.len == 0:
    return

  for e, pkg in app.searchFeed[app.feedSlice]:
    let selected = pkg.name == app.currentPkg.name
    let installed = pkg.name in app.installedPkgs
    let installText = if installed: FA_Times else: FA_Download

    if igSelectable(cstring &"##{e}", selected, size = igVec2(0, igGetFrameHeight() + app.strongFont.fontSize + (style.framePadding.y * 2)), flags = ImGuiSelectableFlags.AllowItemOverlap):
      if pkg.alias.isSome:
        app.currentPkg = app.feed.filterIt(it.name == pkg.alias.get)[0]
      else:
        app.currentPkg = pkg

    igSameLine(); igBeginGroup()
    app.strongFont.igPushFont()
    igText(cstring pkg.name)
    igPopFont()

    if pkg.alias.isSome:
      igTextWithEllipsis(
        &"Alias for {pkg.alias.get}", 
        maxWidth = igGetContentRegionAvail().x - style.itemSpacing.x - igCalcFrameSize(installText).x
      )
      igEndGroup()
      continue
    
    igTextWithEllipsis(
      if pkg.description.len > 0: pkg.description else: "No description.", 
      maxWidth = igGetContentRegionAvail().x - style.itemSpacing.x - igCalcFrameSize(installText).x
    )
    igSameLine(); igCenterCursorX(igCalcFrameSize(installText).x, align = 1)
    
    if igButton(cstring &"{installText}##{e}"):
      if installed:
        app.removePkg(pkg.name)
      else:
        app.installPkg(pkg.name)

    igEndGroup()

proc drawLeftPanel(app: var App) = 
  if igBeginChild("##leftPanel", igVec2(app.splitterSize.a, 0)):
    app.drawPkgsListHeader(); igSeparator()

    if igBeginChild("##pkgsList", flags = makeFlags(NoBackground, AlwaysUseWindowPadding)):
      if igGetScrollY() == 0 and app.feedSlice.a > 0:
        app.feedSlice = max(0, app.feedSlice.a - 50)..app.feedSlice.a
        igSetScrollY(igGetScrollMaxY() - 1)
      elif igGetScrollY() == igGetScrollMaxY() and app.feedSlice.b < app.searchFeed.high:
        app.feedSlice = app.feedSlice.b..min(app.searchFeed.high, app.feedSlice.b + 50)
        igSetScrollY(1)

      app.drawPkgsList()

    igEndChild()

  igEndChild()

proc drawPreviewTags(app: var App, maxWidth: float32) = 
  let style = igGetStyle()

  igPushStyleVar(FrameRounding, 0f)
  igPushStyleColor(ImGuiCol.Button, igGetColorU32(ImGuiCol.Tab))
  igPushStyleColor(ImGuiCol.ButtonHovered, igGetColorU32(ImGuiCol.TabHovered))
  igPushStyleColor(ImGuiCol.ButtonActive, igGetColorU32(ImGuiCol.TabActive))

  let tagsWidth = 
    app.currentPkg.tags.mapIt(igCalcTextSize(cstring it.capitalizeAscii()).x).sum() + 
    (style.framePadding.x * float32(app.currentPkg.tags.len * 2)) + 
    (style.itemSpacing.x * float32 app.currentPkg.tags.len-1)

  igCenterCursorX(if tagsWidth > maxWidth: maxWidth else: tagsWidth, align = 1)

  if igBeginChild("##previewTags", igVec2(if tagsWidth > maxWidth: maxWidth else: tagsWidth, igGetFrameHeight()), flags = makeFlags(NoBackground, NoScrollbar)):
    for e, tag in app.currentPkg.tags:
      if igButton(cstring tag.capitalizeAscii()) and tag notin app.tags:
        app.tags.add tag
        app.filterFeedByTags()
    
      if e < app.currentPkg.tags.len-1:
        igSameLine()

  igEndChild(); igPopStyleColor(3); igPopStyleVar()

  let io = igGetIO()

  if igIsItemHovered(): # To scroll horizontally wihout having to press Shift
    io.keyShift = true
    io.keyMods = ImGuiKeyModFlags.Shift
    app.tagsHovered = true
  elif app.tagsHovered:
    io.keyShift = false
    io.keyMods = ImGuiKeyModFlags.None
    app.tagsHovered = false

proc drawRightPanel(app: var App) = 
  igPushStyleVar(WindowPadding, igVec2(150, 20))

  if igBeginChild("##rightPanel", flags = AlwaysUseWindowPadding):
    let pkg = app.currentPkg

    app.strongFont.igPushFont()
    igText(cstring pkg.name)
    igPopFont()

    igTextWrapped(cstring(if pkg.description.len > 0: pkg.description else: "No description provided."))

    if igButton("Install"):
      app.installPkg(pkg.name)

    if pkg.tags.len > 0:
      igSameLine()  
      app.drawPreviewTags(igGetContentRegionAvail().x)

    igSpacing(); igSeparator(); igSpacing()

    if app.scrollToBottom:
      app.scrollToBottom = false
      igSetNextWindowScroll(igVec2(0, 999999999))

    app.monoFont.igPushFont()
    igInputTextMultiline("##log", cstring app.log, uint app.log.len, igGetContentRegionAvail(), ImGuiInputTextFlags.ReadOnly)
    igPopFont()

  igEndChild()
  igPopStyleVar()

proc loadPkgs(app: var App, path: string) = 
  for pkg in path.parseFile():
    if "alias" in pkg:
      app.feed.add(Package(name: pkg["name"].getStr(), alias: pkg["alias"].getStr().some))
      continue
    
    for tag in pkg["tags"]:
      if tag.getStr() notin app.pkgsTags and tag.getStr().len != 0:
        app.pkgsTags.add(tag.getStr())

    app.feed.add(pkg.to(Package))

  app.pkgsTags.sort()

  app.sortFeed()

  randomize()
  app.currentPkg = app.searchFeed[rand(app.feed.high)]

proc drawPkgs(app: var App) = 
  app.downloader.update()
  app.checkProcess()

  if not app.downloader.exists("packages"):
    app.downloader.download("https://github.com/nim-lang/packages/blob/master/packages.json?raw=true", "packages.json", "packages", replace = true)
  elif app.downloader.succeed("packages") and app.feed.len == 0:
    app.loadPkgs(app.downloader.getPath("packages").get())

  const splitterWidth = 8
  let style = igGetStyle()
  let avail = igGetContentRegionAvail() - igVec2(splitterWidth, 0)

  # Keep splitter proportions on resize
  # And hide the editing zone when not editing
  if app.prevAvail != igVec2(0, 0) and app.prevAvail != avail:
    app.splitterSize = ((app.splitterSize.a / app.prevAvail.x) * avail.x, (app.splitterSize.b / app.prevAvail.x) * avail.x)

  app.prevAvail = avail

  # First time
  if app.splitterSize.a == 0:
    app.splitterSize = (avail.x * 0.2f, avail.x * 0.8f)

  if app.downloader.succeed("packages") or app.offline:
    igSplitter(true, splitterWidth, app.splitterSize.a.addr, app.splitterSize.b.addr, 200, 800, avail.y)
    app.drawLeftPanel()
    igSameLine(spacing = splitterWidth)
    app.drawRightPanel()

  elif app.downloader.running("packages"):
    igCenterCursor(ImVec2(x: 15 * 2, y: (15 + igGetStyle().framePadding.y) * 2))
    igSpinner("##spinner", 15, 6, igGetColorU32(ButtonHovered))

  elif (let errorMsg = app.downloader.getErrorMsg("packages"); errorMsg.isSome):
    let text = "Error fetching packages list: \n" & errorMsg.get().splitLines()[0] & "\n"

    igCenterCursorX(igCalcTextSize(cstring text).x)
    igCenterCursorY(igGetFrameHeight() + igCalcTextSize(cstring text).y + igGetStyle().itemSpacing.y)
    igBeginGroup()
    igTextWrapped(cstring text)

    if igIsItemHovered():
      igSetTooltip("Right click to copy full error")

    if igBeginPopupContextItem("menu"):
      if igMenuItem("Copy"):
        igSetClipboardText(cstring errorMsg.get())
      igEndPopup()

    if fileExists(app.getCacheDir() / "packages.json") and igButton("Offline mode"):
      app.loadPkgs(app.getCacheDir() / "packages.json")
      app.offline = true

    if igButton("Retry") and not app.downloader.running("packages"):
      app.downloader.downloadAgain("packages")
    igEndGroup()

proc drawMain(app: var App) = # Draw the main window
  let viewport = igGetMainViewport()  
  
  app.drawMainMenuBar()
  # Work area is the entire viewport minus main menu bar, task bars, etc.
  igSetNextWindowPos(viewport.workPos)
  igSetNextWindowSize(viewport.workSize)

  if igBegin(cstring app.config["name"].getString(), flags = makeFlags(ImGuiWindowFlags.NoResize, NoDecoration, NoMove)):
    igText(FA_Info & " Application average %.3f ms/frame (%.1f FPS)", 1000f / igGetIO().framerate, igGetIO().framerate)
    app.drawPkgs()

  igEnd()

  # GLFW clipboard -> ImGui clipboard
  if not app.win.getClipboardString().isNil and $app.win.getClipboardString() != app.lastClipboard:
    igsetClipboardText(app.win.getClipboardString())
    app.lastClipboard = $app.win.getClipboardString()

  # ImGui clipboard -> GLFW clipboard
  if not igGetClipboardText().isNil and $igGetClipboardText() != app.lastClipboard:
    app.win.setClipboardString(igGetClipboardText())
    app.lastClipboard = $igGetClipboardText()

proc render(app: var App) = # Called in the main loop
  # Poll and handle events (inputs, window resize, etc.)
  glfwPollEvents() # Use glfwWaitEvents() to only draw on events (more efficient)

  # Start Dear ImGui Frame
  igOpenGL3NewFrame()
  igGlfwNewFrame()
  igNewFrame()

  # Draw application
  app.drawMain()

  # Render
  igRender()

  var displayW, displayH: int32
  let bgColor = igColorConvertU32ToFloat4(uint32 WindowBg)

  app.win.getFramebufferSize(displayW.addr, displayH.addr)
  glViewport(0, 0, displayW, displayH)
  glClearColor(bgColor.x, bgColor.y, bgColor.z, bgColor.w)
  glClear(GL_COLOR_BUFFER_BIT)

  igOpenGL3RenderDrawData(igGetDrawData())  

  app.win.makeContextCurrent()
  app.win.swapBuffers()

proc initWindow(app: var App) = 
  glfwWindowHint(GLFWContextVersionMajor, 3)
  glfwWindowHint(GLFWContextVersionMinor, 3)
  glfwWindowHint(GLFWOpenglForwardCompat, GLFW_TRUE)
  glfwWindowHint(GLFWOpenglProfile, GLFW_OPENGL_CORE_PROFILE)
  glfwWindowHint(GLFWResizable, GLFW_TRUE)

  app.win = glfwCreateWindow(
    int32 app.prefs{"win", "width"}.getInt(), 
    int32 app.prefs{"win", "height"}.getInt(), 
    cstring app.config["name"].getString(), 
    icon = false # Do not use default icon
  )

  if app.win == nil:
    quit(-1)

  # Set the window icon
  var icon = initGLFWImage(app.config["iconPath"].getData().readImageFromMemory())
  app.win.setWindowIcon(1, icon.addr)

  app.win.setWindowSizeLimits(app.config["minSize"][0].getInt().int32, app.config["minSize"][1].getInt().int32, GLFW_DONT_CARE, GLFW_DONT_CARE) # minWidth, minHeight, maxWidth, maxHeight

  # If negative pos, center the window in the first monitor
  if app.prefs{"win", "x"}.getInt() < 0 or app.prefs{"win", "y"}.getInt() < 0:
    var monitorX, monitorY, count: int32
    let monitors = glfwGetMonitors(count.addr)
    let videoMode = monitors[0].getVideoMode()

    monitors[0].getMonitorPos(monitorX.addr, monitorY.addr)
    app.win.setWindowPos(
      monitorX + int32((videoMode.width - int app.prefs{"win", "width"}.getInt()) / 2), 
      monitorY + int32((videoMode.height - int app.prefs{"win", "height"}.getInt()) / 2)
    )
  else:
    app.win.setWindowPos(app.prefs{"win", "x"}.getInt().int32, app.prefs{"win", "y"}.getInt().int32)

proc initPrefs(app: var App) = 
  app.prefs = initPrefs(
    path = (app.getCacheDir() / app.config["name"].getString()).changeFileExt("toml"), 
    default = toToml {
      win: {
        x: -1, # Negative numbers center the window
        y: -1,
        width: 600,
        height: 650
      }
    }
  )

proc initApp(config: TomlValueRef): App = 
  result = App(
    config: config, cache: newTTable(), 
    tagsBuffer: newString(100), searchBuffer: newString(100), 
  )
  result.initPrefs()
  result.initSettings(result.config["settings"])

  result.downloader = initDownloader(result.getCacheDir(), 1)

  startProcesses()
  result.runCmd(["--version"])

proc terminate(app: var App) = 
  endProcesses()

  var x, y, width, height: int32

  app.win.getWindowPos(x.addr, y.addr)
  app.win.getWindowSize(width.addr, height.addr)
  
  app.prefs{"win", "x"} = x
  app.prefs{"win", "y"} = y
  app.prefs{"win", "width"} = width
  app.prefs{"win", "height"} = height

  app.prefs.save()

proc main() =
  var app = initApp(Toml.decode(configPath.getData(), TomlValueRef))

  # Setup Window
  doAssert glfwInit()
  app.initWindow()
  
  app.win.makeContextCurrent()
  glfwSwapInterval(1) # Enable vsync

  doAssert glInit()

  # Setup Dear ImGui context
  igCreateContext()
  let io = igGetIO()
  io.iniFilename = nil # Disable .ini config file

  # Setup Dear ImGui style using ImStyle
  setStyleFromToml(Toml.decode(app.config["stylePath"].getData(), TomlValueRef))

  # Setup Platform/Renderer backends
  doAssert igGlfwInitForOpenGL(app.win, true)
  doAssert igOpenGL3Init()

  # Load fonts
  app.font = io.fonts.igAddFontFromMemoryTTF(app.config["fontPath"].getData(), app.config["fontSize"].getFloat())

  # Merge ForkAwesome icon font
  var config = utils.newImFontConfig(mergeMode = true)
  var ranges = [FA_Min.uint16,  FA_Max.uint16]

  io.fonts.igAddFontFromMemoryTTF(app.config["iconFontPath"].getData(), app.config["fontSize"].getFloat(), config.addr, ranges[0].addr)

  # Strong font
  app.strongFont = io.fonts.igAddFontFromMemoryTTF(app.config["strongFontPath"].getData(), app.config["fontSize"].getFloat() + 2)
  io.fonts.igAddFontFromMemoryTTF(app.config["iconFontPath"].getData(), app.config["fontSize"].getFloat() + 2, config.addr, ranges[0].addr)

  # Monospace font
  app.monoFont = io.fonts.igAddFontFromMemoryTTF(app.config["monoFontPath"].getData(), app.config["fontSize"].getFloat())

  # Main loop
  while not app.win.windowShouldClose:
    app.render()

  # Cleanup
  igOpenGL3Shutdown()
  igGlfwShutdown()
  
  igDestroyContext()
  
  app.terminate()
  app.win.destroyWindow()
  glfwTerminate()

when isMainModule:
  main()
