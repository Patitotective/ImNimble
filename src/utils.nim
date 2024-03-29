import std/[typetraits, strformat, enumutils, strbasics, strutils, macros, times, math, os]
import chroma
import downit
import niprefs
import openurl
import stb_image/read as stbi
import nimgl/[opengl, imgui, glfw]

import icons

export enumutils

type
  SettingTypes* = enum
    Input # Input text
    Check # Checkbox
    Slider # Int slider
    FSlider # Float slider
    Spin # Int spin
    FSpin # Float spin
    Combo
    Radio # Radio button
    Color3 # Color edit RGB
    Color4 # Color edit RGBA
    Section

  ImageData* = tuple[image: seq[byte], width, height: int]

  Package* = object
    name*, url*, description*, license*: string
    tags*: seq[string]
    web*, doc*, alias*: Option[string]

  App* = object
    win*: GLFWWindow
    font*, strongFont*, monoFont*: ptr ImFont
    prefs*: Prefs
    cache*: TomlValueRef # Settings cache
    config*: TomlValueRef # Prefs table
    lastClipboard*: string
    downloader*: Downloader

    offline*: bool # Browse pre-downloaded packages list
    nimbleNotInstalled*: bool

    log*: string
    running*: bool # Is there a process running?
    scrollToBottom*: bool # Scroll to console's bottom

    feed*: seq[Package]
    taggedFeed*: seq[Package] # feed filtered by tags
    searchFeed*: seq[Package] # taggedFeed filtered by searchBuffer
    feedSlice*: Slice[int] # Slice to show
    aliases*: Table[string, string]

    prevAvail*: ImVec2
    splitterSize*: tuple[a, b: float32]

    currentSort*: int
    currentPkg*: Package
    tagsBuffer*, searchBuffer*: string
    tags*, pkgsTags*, installedPkgs*: seq[string]
    tagsHovered*: bool # Boolean to set IO key mod shift to false when preview tags are not hovered

proc `+`*(vec1, vec2: ImVec2): ImVec2 = 
  ImVec2(x: vec1.x + vec2.x, y: vec1.y + vec2.y)

proc `-`*(vec1, vec2: ImVec2): ImVec2 = 
  ImVec2(x: vec1.x - vec2.x, y: vec1.y - vec2.y)

proc `*`*(vec1, vec2: ImVec2): ImVec2 = 
  ImVec2(x: vec1.x * vec2.x, y: vec1.y * vec2.y)

proc `/`*(vec1, vec2: ImVec2): ImVec2 = 
  ImVec2(x: vec1.x / vec2.x, y: vec1.y / vec2.y)

proc `+`*(vec: ImVec2, val: float32): ImVec2 = 
  ImVec2(x: vec.x + val, y: vec.y + val)

proc `-`*(vec: ImVec2, val: float32): ImVec2 = 
  ImVec2(x: vec.x - val, y: vec.y - val)

proc `*`*(vec: ImVec2, val: float32): ImVec2 = 
  ImVec2(x: vec.x * val, y: vec.y * val)

proc `/`*(vec: ImVec2, val: float32): ImVec2 = 
  ImVec2(x: vec.x / val, y: vec.y / val)

proc `+=`*(vec1: var ImVec2, vec2: ImVec2) = 
  vec1.x += vec2.x
  vec1.y += vec2.y

proc `-=`*(vec1: var ImVec2, vec2: ImVec2) = 
  vec1.x -= vec2.x
  vec1.y -= vec2.y

proc `*=`*(vec1: var ImVec2, vec2: ImVec2) = 
  vec1.x *= vec2.x
  vec1.y *= vec2.y

proc `/=`*(vec1: var ImVec2, vec2: ImVec2) = 
  vec1.x /= vec2.x
  vec1.y /= vec2.y

proc igVec2*(x, y: float32): ImVec2 = ImVec2(x: x, y: y)

proc igVec4*(x, y, z, w: float32): ImVec4 = ImVec4(x: x, y: y, z: z, w: w)

proc igVec4*(color: Color): ImVec4 = ImVec4(x: color.r, y: color.g, z: color.b, w: color.a)

proc igHSV*(h, s, v: float32, a: float32 = 1f): ImColor = 
  result.addr.hSVNonUDT(h, s, v, a)

proc igGetContentRegionAvail*(): ImVec2 = 
  igGetContentRegionAvailNonUDT(result.addr)

proc igGetWindowContentRegionMax*(): ImVec2 = 
  igGetWindowContentRegionMaxNonUDT(result.addr)

proc igGetWindowPos*(): ImVec2 = 
  igGetWindowPosNonUDT(result.addr)

proc igGetItemRectMax*(): ImVec2 = 
  igGetItemRectMaxNonUDT(result.addr)

proc igGetItemRectMin*(): ImVec2 = 
  igGetItemRectMinNonUDT(result.addr)

proc igGetItemRectSize*(): ImVec2 = 
  igGetItemRectSizeNonUDT(result.addr)

proc igCalcTextSize*(text: cstring, text_end: cstring = nil, hide_text_after_double_hash: bool = false, wrap_width: float32 = -1.0'f32): ImVec2 = 
  igCalcTextSizeNonUDT(result.addr, text, text_end, hide_text_after_double_hash, wrap_width)

proc igCalcFrameSize*(text: string): ImVec2 = 
  igCalcTextSize(cstring text) + (igGetStyle().framePadding * 2)

proc igCalcItemSize*(size: ImVec2, default_w: float32, default_h: float32): ImVec2 = 
  igCalcItemSizeNonUDT(result.addr, size, default_w, default_h)

proc igColorConvertU32ToFloat4*(color: uint32): ImVec4 = 
  igColorConvertU32ToFloat4NonUDT(result.addr, color)

proc getCenter*(self: ptr ImGuiViewport): ImVec2 = 
  getCenterNonUDT(result.addr, self)

proc igCenterCursorX*(width: float32, align: float = 0.5f, avail = igGetContentRegionAvail().x) = 
  let off = (avail - width) * align
  
  if off > 0:
    igSetCursorPosX(igGetCursorPosX() + off)

proc igCenterCursorY*(height: float32, align: float = 0.5f, avail = igGetContentRegionAvail().y) = 
  let off = (avail - height) * align
  
  if off > 0:
    igSetCursorPosY(igGetCursorPosY() + off)

proc igCenterCursor*(size: ImVec2, alignX: float = 0.5f, alignY: float = 0.5f, avail = igGetContentRegionAvail()) = 
  igCenterCursorX(size.x, alignX, avail.x)
  igCenterCursorY(size.y, alignY, avail.y)

proc igHelpMarker*(text: string) = 
  igTextDisabled("(?)")
  if igIsItemHovered():
    igBeginTooltip()
    igPushTextWrapPos(igGetFontSize() * 35.0)
    igTextUnformatted(text)
    igPopTextWrapPos()
    igEndTooltip()

proc newImFontConfig*(mergeMode = false): ImFontConfig =
  result.fontDataOwnedByAtlas = true
  result.fontNo = 0
  result.oversampleH = 3
  result.oversampleV = 1
  result.pixelSnapH = true
  result.glyphMaxAdvanceX = float.high
  result.rasterizerMultiply = 1.0
  result.mergeMode = mergeMode

proc igAddFontFromMemoryTTF*(self: ptr ImFontAtlas, data: string, size_pixels: float32, font_cfg: ptr ImFontConfig = nil, glyph_ranges: ptr ImWchar = nil): ptr ImFont {.discardable.} = 
  let igFontStr = cast[cstring](igMemAlloc(data.len.uint))
  igFontStr[0].unsafeAddr.copyMem(data[0].unsafeAddr, data.len)
  result = self.addFontFromMemoryTTF(igFontStr, data.len.int32, sizePixels, font_cfg, glyph_ranges)

proc igSplitter*(split_vertically: bool, thickness: float32, size1, size2: ptr float32, min_size1, min_size2: float32, splitter_long_axis_size = -1f): bool {.discardable.} = 
  let context = igGetCurrentContext()
  let window = context.currentWindow
  let id = window.getID("##Splitter")
  var bb: ImRect
  bb.min = window.dc.cursorPos + (if split_vertically: igVec2(size1[], 0f) else: igVec2(0f, size1[]))
  bb.max = bb.min + igCalcItemSize(if split_vertically: igVec2(thickness, splitter_long_axis_size) else: igVec2(splitter_long_axis_size, thickness), 0f, 0f)
  result = igSplitterBehavior(bb, id, if split_vertically: ImGuiAxis.X else: ImGuiAxis.Y, size1, size2, min_size1, min_size2, 0f)

proc igSpinner*(label: string, radius: float, thickness: float32, color: uint32) = 
  let window = igGetCurrentWindow()
  if window.skipItems:
    return
  
  let
    context = igGetCurrentContext()
    style = context.style
    id = igGetID(label)
  
    pos = window.dc.cursorPos
    size = ImVec2(x: radius * 2, y: (radius + style.framePadding.y) * 2)

    bb = ImRect(min: pos, max: ImVec2(x: pos.x + size.x, y: pos.y + size.y));
  igItemSize(bb, style.framePadding.y)

  if not igItemAdd(bb, id):
      return
  
  window.drawList.pathClear()
  
  let
    numSegments = 30
    start = abs(sin(context.time * 1.8f) * (numSegments - 5).float)
  
  let
    aMin = PI * 2f * start / numSegments.float
    aMax = PI * 2f * ((numSegments - 3) / numSegments).float

    centre = ImVec2(x: pos.x + radius, y: pos.y + radius + style.framePadding.y)

  for i in 0..<numSegments:
    let a = aMin + i / numSegments * (aMax - aMin)
    window.drawList.pathLineTo(ImVec2(x: centre.x + cos(a + context.time * 8) * radius, y: centre.y + sin(a + context.time * 8) * radius))

  window.drawList.pathStroke(color, thickness = thickness)

proc igTextWithEllipsis*(text: string, maxWidth: float32 = igGetContentRegionAvail().x, ellipsisText: string = "...") = 
  var text = text
  var width = igCalcTextSize(cstring text).x
  let ellipsisWidth = igCalcTextSize(cstring ellipsisText).x

  if width > maxWidth:
    while width + ellipsisWidth > maxWidth and text.len > ellipsisText.len:
      text = text[0..^ellipsisText.len]
      width = igCalcTextSize(cstring text).x

    igText(cstring text & ellipsisText)
  else:
    igText(cstring text)

proc igAddUnderLine*(col: uint32) = 
  var min = igGetItemRectMin()
  let max = igGetItemRectMax()

  min.y = max.y
  igGetWindowDrawList().addLine(min, max, col, 1f)

proc igClickableText*(text: string, sameLineBefore, sameLineAfter = true): bool = 
  if sameLineBefore: igSameLine(0, 0)

  igPushStyleColor(ImGuiCol.Text, parseHtmlColor("#4296F9").igVec4())
  igText(cstring text)
  igPopStyleColor()

  if igIsItemHovered():
    if igIsMouseClicked(ImGuiMouseButton.Left):
      result = true

    igAddUnderLine(parseHtmlColor("#4296F9").igVec4().igColorConvertFloat4ToU32())

  if sameLineAfter: igSameLine(0, 0)

proc igUrlText*(url: string, text = "", sameLineBefore, sameLineAfter = true) = 
  if igClickableText(if text.len > 0: text else: url, sameLineBefore, sameLineAfter):
    url.openUrl()

  if igIsItemHovered():
    igSetTooltip(cstring url & " " & FA_ExternalLink)

# To be able to print large holey enums
macro enumFullRange*(a: typed): untyped =
  newNimNode(nnkBracket).add(a.getType[1][1..^1])

iterator items*(T: typedesc[HoleyEnum]): T =
  for x in T.enumFullRange:
    yield x

proc getEnumValues*[T: enum](): seq[string] = 
  for i in T:
    result.add $i

proc parseEnum*[T: enum](node: TomlValueRef): T = 
  assert node.kind == TomlKind.String

  try:
    result = parseEnum[T](node.getString().capitalizeAscii())
  except:
    raise newException(ValueError, &"Invalid enum value {node.getString()} for {$T}. Valid values are {$getEnumValues[T]()}")

proc makeFlags*[T: enum](flags: varargs[T]): T =
  ## Mix multiple flags of a specific enum
  var res = 0
  for x in flags:
    res = res or int(x)

  result = T res

proc getFlags*[T: enum](node: TomlValueRef): T = 
  ## Similar to parseEnum but this one mixes multiple enum values if node.kind == PSeq
  case node.kind:
  of TomlKind.String, TomlKind.Int:
    result = parseEnum[T](node)
  of TomlKind.Array:
    var flags: seq[T]
    for i in node.getArray():
      flags.add parseEnum[T](i)

    result = makeFlags(flags)
  else:
    raise newException(ValueError, "Invalid kind {node.kind} for {$T} enum. Valid kinds are PInt, PString or PSeq") 

proc parseColor3*(node: TomlValueRef): array[3, float32] = 
  assert not node.isNil and node.kind in {TomlKind.String, TomlKind.Array}

  case node.kind
  of TomlKind.String:
    let color = node.getString().parseHtmlColor()
    result[0] = color.r
    result[1] = color.g
    result[2] = color.b 
  of TomlKind.Array:
    assert node.len == 3
    result[0] = node[0].getFloat()
    result[1] = node[1].getFloat()
    result[2] = node[2].getFloat()
  else:
    raise newException(ValueError, &"Invalid color RGB {node}")

proc parseColor4*(node: TomlValueRef): array[4, float32] = 
  assert not node.isNil and node.kind in {TomlKind.String, TomlKind.Array}

  case node.kind
  of TomlKind.String:
    let color = node.getString().parseHtmlColor()
    result[0] = color.r
    result[1] = color.g
    result[2] = color.b 
    result[3] = color.a
  of TomlKind.Array:
    assert node.len == 4
    result[0] = node[0].getFloat()
    result[1] = node[1].getFloat()
    result[2] = node[2].getFloat()
    result[3] = node[3].getFloat()
  else:
    raise newException(ValueError, &"Invalid color RGBA {node}")

proc initGLFWImage*(data: ImageData): GLFWImage = 
  result = GLFWImage(pixels: cast[ptr cuchar](data.image[0].unsafeAddr), width: int32 data.width, height: int32 data.height)

proc readImageFromMemory*(data: string): ImageData = 
  var channels: int
  result.image = stbi.loadFromMemory(cast[seq[byte]](data), result.width, result.height, channels, stbi.Default)

proc loadTextureFromData*(data: var ImageData, outTexture: var GLuint) =
    # Create a OpenGL texture identifier
    glGenTextures(1, outTexture.addr)
    glBindTexture(GL_TEXTURE_2D, outTexture)

    # Setup filtering parameters for display
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint) # This is required on WebGL for non power-of-two textures
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint) # Same

    # Upload pixels into texture
    # if defined(GL_UNPACK_ROW_LENGTH) && !defined(__EMSCRIPTEN__)
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)

    glTexImage2D(GL_TEXTURE_2D, GLint 0, GL_RGBA.GLint, GLsizei data.width, GLsizei data.height, GLint 0, GL_RGBA, GL_UNSIGNED_BYTE, data.image[0].addr)

proc removeInside*(text: string, open, close: char): tuple[text: string, inside: string] = 
  ## Remove the characters inside open..close from text, return text and the removed characters
  runnableExamples:
    assert "Hello<World>".removeInside('<', '>') == ("Hello", "World")
  var inside = false
  for i in text:
    if i == open:
      inside = true
      continue

    if not inside:
      result.text.add i

    if i == close:
      inside = false

    if inside:
      result.inside.add i

proc initSettings*(app: var App, settings: TomlValueRef, parent = "", overwrite = false) = 
  ## Init the settings defined in config["settings"] and the cache.
  for name, data in settings: 
    let settingType = parseEnum[SettingTypes](data["type"])
    if settingType == Section:
      app.initSettings(data["content"], parent = name, overwrite)
    
    elif parent.len > 0:

      if parent notin app.prefs or overwrite:
        app.prefs[parent] = newTTable()
      if name notin app.prefs[parent] or overwrite:
        app.prefs{parent, name} = data["default"]

      app.cache{parent, name} = app.prefs{parent, name}
    else:
      if name notin app.prefs or overwrite:
        app.prefs[name] = data["default"]
      
      app.cache[name] = app.prefs[name]

proc pushString*(str: var string, val: string) = 
  if val.len < str.len:
    str[0..val.len] = val & '\0'
  else:
    str[0..str.high] = val[0..str.high]

proc newString*(length: int, default: string): string = 
  result = newString(length)
  result.pushString(default)

proc cleanString*(str: string): string = 
  if '\0' in str:
    str[0..<str.find('\0')].strip()
  else:
    str.strip()

proc updatePrefs*(app: var App) = 
  # Update the values depending on the preferences here
  echo "Updating preferences..."

proc passFilter*(buffer: string, str: string): bool = 
  buffer.cleanString().toLowerAscii() in str.toLowerAscii()

proc addLine*(s: var string, val: openArray[char]) = 
  s.add(val)
  s.add('\n')

template lastLine*(str: string): openArray[char] = 
  if (let idx = str.rFind("\n"); idx) > 0:
    str.toOpenArray(idx, str.len)
  else:
    str
