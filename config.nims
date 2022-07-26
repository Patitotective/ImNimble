switch("backend", "cpp")
switch("warning", "HoleEnumConv:off")
switch("define", "tomlOrderedTable")
switch("define", "ssl")

when defined(Windows):
  switch("passC", "-static")
  switch("passL", "-static")
