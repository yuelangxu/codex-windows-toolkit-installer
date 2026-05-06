# Codex Office Typesetting Toolkit

This toolkit layer installs and wires together free/open tools for PowerPoint,
LibreOffice, lesson decks, worksheets, exams, print-ready handouts, and
AI-agent-friendly PowerPoint automation.

## Installed tool families

- PowerPoint add-ins: IguanaTex, BrightSlide, Instrumenta, THOR, and Power Up Kit
- LibreOffice equation/export extensions: TexMaths and Writer2LaTeX
- TeX engine: MiKTeX with auto package install
- Modern document engine: Typst
- Markdown deck engine: Marp CLI
- Vector and diagram tools: Inkscape and draw.io
- PDF preview and print layout: SumatraPDF and Scribus
- Conversion helpers: Pandoc, ImageMagick, Ghostscript when present
- PowerPoint COM command layer: `ppt-*` automation for slides, shapes, gradients, exports, and add-ins
- Course-pack workflow: scaffold once, then emit slide deck, editable PPTX, slide PDF, and printable handout PDF

## PowerShell commands

After profile integration is enabled, open a new PowerShell window and run:

```powershell
office-tools
office-tool-paths typst marp latex
coursepack-init .\week05 -Title "Quantum Tunneling" -Subtitle "Week 5"
coursepack-build .\week05 -OpenOutput
typst-pdf .\exam.typ .\exam.pdf
tex-xe .\exam-cn.tex
marp-pptx .\lesson.md .\lesson.pptx
marp-pdf .\lesson.md .\lesson.pdf
marp-pptx-editable .\lesson.md .\lesson-editable.pptx
office-samples
ppt-new .\lesson.pptx -Width 13.333 -Height 7.5 -Unit in
ppt-add-shape .\lesson.pptx -SlideIndex 1 -ShapeType roundedRect -Left 0.8 -Top 1.2 -Width 3.5 -Height 1.1 -FillColor #143B6B -FillColor2 #5DA9E9 -Gradient
ppt-spec .\deck-spec.json
ppt-addin-list
``` 

The profile also exports global variables such as:

- `$global:TypstExe`
- `$global:MarpCmd`
- `$global:ChromiumExe`
- `$global:XeLaTeXExe`
- `$global:PdfLaTeXExe`
- `$global:LatexMkExe`
- `$global:DvisvgmExe`
- `$global:LibreOfficeExe`
- `$global:LibreOfficeUnopkgExe`
- `$global:InkscapeExe`
- `$global:DrawIoExe`
- `$global:SumatraPdfExe`
- `$global:ScribusExe`
- `$global:IguanaTexAddIn`
- `$global:BrightSlideAddIn`
- `$global:InstrumentaAddIn`
- `$global:ThorAddIn`
- `$global:PowerUpKitAddIn`
- `$global:TexMathsOxt`
- `$global:OfficeTypesettingToolsRoot`

The local Office helper root is:

- `%LOCALAPPDATA%\Programs\OfficeTypesettingTools`

IguanaTex is registered from:

- `%APPDATA%\Microsoft\AddIns\IguanaTex_v1_62_1.ppam`

Power Up Kit support files are staged under:

- `%USERPROFILE%\Documents\PowerShell\Toolkit\examples\powerpoint-addins`

## Course-pack workflow

The new `coursepack-*` commands are meant for teaching material and textbook-like
builds:

```powershell
coursepack-init .\week05 -Title "Quantum Tunneling" -Subtitle "Week 5"
coursepack-build .\week05
```

That produces:

- `output\<slug>.pptx`
- `output\<slug>-editable.pptx`
- `output\<slug>-slides.pdf`
- `output\<slug>-handout.pdf`

## PowerPoint automation workflow

The `ppt-*` commands use the desktop PowerPoint COM API so AI agents can do more
than just export:

- create or resize decks
- draw shapes and text boxes
- apply gradients, lines, glow, and shadows
- place and style images
- align, distribute, and reorder shapes
- export to PDF or slide images
- register add-ins for durable auto-load

## Installer switch

Use the top-level installer with:

```powershell
.\Install-CodexWindowsToolkit.ps1 -AutoApprove -IncludeProfileIntegration -IncludeOfficeTypesettingTools
```

Use `-SkipLibreOfficeExtensions` or `-SkipPowerPointAddIn` on
`Install-CodexOfficeTypesettingTools.ps1` only when you need to install command
line tools without changing Office add-ins.
