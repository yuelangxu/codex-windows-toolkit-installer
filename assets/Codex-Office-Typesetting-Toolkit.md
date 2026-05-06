# Codex Office Typesetting Toolkit

This toolkit layer installs and wires together free/open tools for PowerPoint,
LibreOffice, lesson decks, worksheets, exams, and print-ready handouts.

## Installed tool families

- PowerPoint equation add-in: IguanaTex
- LibreOffice equation/export extensions: TexMaths and Writer2LaTeX
- TeX engine: MiKTeX with auto package install
- Modern document engine: Typst
- Markdown deck engine: Marp CLI
- Vector and diagram tools: Inkscape and draw.io
- PDF preview and print layout: SumatraPDF and Scribus
- Conversion helpers: Pandoc, ImageMagick, Ghostscript when present

## PowerShell commands

After profile integration is enabled, open a new PowerShell window and run:

```powershell
office-tools
office-tool-paths typst marp latex
typst-pdf .\exam.typ .\exam.pdf
tex-xe .\exam-cn.tex
marp-pptx .\lesson.md .\lesson.pptx
marp-pdf .\lesson.md .\lesson.pdf
marp-pptx-editable .\lesson.md .\lesson-editable.pptx
office-samples
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
- `$global:TexMathsOxt`
- `$global:OfficeTypesettingToolsRoot`

The local Office helper root is:

- `%LOCALAPPDATA%\Programs\OfficeTypesettingTools`

IguanaTex is registered from:

- `%APPDATA%\Microsoft\AddIns\IguanaTex_v1_62_1.ppam`

## Installer switch

Use the top-level installer with:

```powershell
.\Install-CodexWindowsToolkit.ps1 -AutoApprove -IncludeProfileIntegration -IncludeOfficeTypesettingTools
```

Use `-SkipLibreOfficeExtensions` or `-SkipPowerPointAddIn` on
`Install-CodexOfficeTypesettingTools.ps1` only when you need to install command
line tools without changing Office add-ins.
