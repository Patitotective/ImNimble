# Package

version          = "0.1.0"
author           = "Patitotective"
description      = "A Dear ImGui Nimble client"
license          = "MIT"
namedBin["main"] = "ImExample"
backend          = "cpp"

# Dependencies

requires "nim >= 1.6.2"
requires "nake >= 1.9.4"
requires "nimgl >= 1.3.2"
requires "chroma >= 0.2.4"
requires "stb_image >= 2.5"
requires "openurl >= 2.0.1"
requires "downit >= 0.2.1 & < 0.3.0"
requires "imstyle >= 0.3.4 & < 0.4.0"
requires "niprefs >= 0.3.4 & < 0.4.0"
requires "tinydialogs >= 1.0.0 & < 2.0.0"

import std/[strformat, os]

let arch = if existsEnv("ARCH"): getEnv("ARCH") else: "amd64"
let outPath = if existsEnv("OUTPATH"): getEnv("OUTPATH") else: &"{namedBin[\"main\"]}-{version}-{arch}" & (when defined(Windows): ".exe" else: "")
let flags = getEnv("FLAGS")

task buildApp, "Build the application":
  exec "nimble install -d -y"
  exec fmt"nim cpp -d:release --app:gui --out:{outPath} --cpu:{arch} {flags} main.nim"

task runApp, "Build and run the application":
  exec "nimble buildApp"

  exec fmt"./{outPath}"

