@{
    ToolkitName = 'Codex Windows Toolkit'
    ToolkitRootName = 'Toolkit'

    WingetPackages = @(
        @{
            Id = 'Microsoft.PowerShell'
            DisplayName = 'PowerShell 7'
            Commands = @('pwsh')
            Category = 'Core'
        }
        @{
            Id = 'Git.Git'
            DisplayName = 'Git'
            Commands = @('git')
            Category = 'Core'
        }
        @{
            Id = 'GitHub.cli'
            DisplayName = 'GitHub CLI'
            Commands = @('gh')
            Category = 'Core'
        }
        @{
            Id = 'BurntSushi.ripgrep.MSVC'
            DisplayName = 'ripgrep'
            Commands = @('rg')
            Category = 'Core'
        }
        @{
            Id = 'JernejSimoncic.Wget'
            DisplayName = 'Wget'
            Commands = @('wget.exe')
            Category = 'Core'
        }
        @{
            Id = 'OpenJS.NodeJS.LTS'
            DisplayName = 'Node.js LTS'
            Commands = @('node', 'npm')
            Category = 'Core'
        }
        @{
            Id = 'Google.PlatformTools'
            DisplayName = 'Android SDK Platform-Tools'
            Commands = @('adb')
            Category = 'Mobile'
        }
        @{
            Id = 'QPDF.QPDF'
            DisplayName = 'QPDF'
            Commands = @('qpdf')
            Category = 'Document'
        }
        @{
            Id = 'oschwartz10612.Poppler'
            DisplayName = 'Poppler'
            Commands = @('pdftotext', 'pdftoppm')
            Category = 'Document'
        }
        @{
            Id = 'ArtifexSoftware.mutool'
            DisplayName = 'mutool'
            Commands = @('mutool')
            Category = 'Document'
        }
        @{
            Id = 'sharkdp.fd'
            DisplayName = 'fd'
            Commands = @('fd')
            Category = 'Core'
        }
        @{
            Id = 'junegunn.fzf'
            DisplayName = 'fzf'
            Commands = @('fzf')
            Category = 'Core'
        }
        @{
            Id = 'jqlang.jq'
            DisplayName = 'jq'
            Commands = @('jq')
            Category = 'Core'
        }
        @{
            Id = 'MikeFarah.yq'
            DisplayName = 'yq'
            Commands = @('yq')
            Category = 'Core'
        }
        @{
            Id = 'astral-sh.uv'
            DisplayName = 'uv'
            Commands = @('uv')
            Category = 'Core'
        }
        @{
            Id = 'pnpm.pnpm'
            DisplayName = 'pnpm'
            Commands = @('pnpm')
            Category = 'Core'
        }
        @{
            Id = 'sharkdp.bat'
            DisplayName = 'bat'
            Commands = @('bat')
            Category = 'Core'
        }
        @{
            Id = 'dandavison.delta'
            DisplayName = 'delta'
            Commands = @('delta')
            Category = 'Core'
        }
        @{
            Id = 'eza-community.eza'
            DisplayName = 'eza'
            Commands = @('eza')
            Category = 'Core'
        }
        @{
            Id = 'ajeetdsouza.zoxide'
            DisplayName = 'zoxide'
            Commands = @('zoxide')
            Category = 'Core'
        }
        @{
            Id = 'Starship.Starship'
            DisplayName = 'starship'
            Commands = @('starship')
            Category = 'Core'
        }
        @{
            Id = 'JesseDuffield.lazygit'
            DisplayName = 'lazygit'
            Commands = @('lazygit')
            Category = 'Core'
        }
        @{
            Id = 'Casey.Just'
            DisplayName = 'just'
            Commands = @('just')
            Category = 'Core'
        }
        @{
            Id = 'sharkdp.hyperfine'
            DisplayName = 'hyperfine'
            Commands = @('hyperfine')
            Category = 'Core'
        }
        @{
            Id = '7zip.7zip'
            DisplayName = '7-Zip'
            Commands = @('7z')
            Category = 'Core'
        }
        @{
            Id = 'chmln.sd'
            DisplayName = 'sd'
            Commands = @('sd')
            Category = 'Core'
        }
        @{
            Id = 'Python.Python.3.11'
            DisplayName = 'Python 3.11'
            Commands = @('py')
            Category = 'Runtime'
        }
        @{
            Id = 'UB-Mannheim.TesseractOCR'
            DisplayName = 'Tesseract OCR'
            Commands = @('tesseract')
            Category = 'OCR'
        }
        @{
            Id = 'Microsoft.PowerToys'
            DisplayName = 'PowerToys'
            Commands = @()
            Category = 'OCR'
        }
        @{
            Id = 'cb4960.Capture2Text'
            DisplayName = 'Capture2Text'
            Commands = @('Capture2Text_CLI')
            Category = 'OCR'
        }
        @{
            Id = 'Ollama.Ollama'
            DisplayName = 'Ollama'
            Commands = @('ollama')
            Category = 'AI'
        }
        @{
            Id = 'ImageMagick.Q16'
            DisplayName = 'ImageMagick Q16'
            Commands = @('magick')
            Category = 'Media'
        }
    )

    PowerShellModules = @(
        @{
            Name = 'Terminal-Icons'
            DisplayName = 'Terminal-Icons'
            Category = 'PowerShell'
        }
        @{
            Name = 'PSFzf'
            DisplayName = 'PSFzf'
            Category = 'PowerShell'
        }
        @{
            Name = 'posh-git'
            DisplayName = 'posh-git'
            Category = 'PowerShell'
        }
        @{
            Name = 'CompletionPredictor'
            DisplayName = 'CompletionPredictor'
            Category = 'PowerShell'
        }
    )

    OptionalWingetPackages = @(
        @{
            Id = 'ducaale.xh'
            DisplayName = 'xh'
            Commands = @('xh')
            Category = 'Optional'
        }
        @{
            Id = 'jdx.mise'
            DisplayName = 'mise-en-place'
            Commands = @('mise')
            Category = 'Optional'
        }
        @{
            Id = 'bootandy.dust'
            DisplayName = 'dust'
            Commands = @('dust')
            Category = 'Optional'
        }
        @{
            Id = 'dalance.procs'
            DisplayName = 'procs'
            Commands = @('procs')
            Category = 'Optional'
        }
        @{
            Id = 'Genymobile.scrcpy'
            DisplayName = 'scrcpy'
            Commands = @('scrcpy')
            Category = 'Optional'
        }
    )

    WebAuthPythonModules = @(
        @{
            Package = 'requests'
            ImportName = 'requests'
        }
        @{
            Package = 'beautifulsoup4'
            ImportName = 'bs4'
        }
        @{
            Package = 'playwright'
            ImportName = 'playwright'
        }
    )

    PythonModules = @(
        @{
            Package = 'easyocr'
            ImportName = 'easyocr'
        }
        @{
            Package = 'paddleocr'
            ImportName = 'paddleocr'
        }
        @{
            Package = 'ocrmypdf'
            ImportName = 'ocrmypdf'
        }
        @{
            Package = 'nougat-ocr'
            ImportName = 'nougat'
        }
        @{
            Package = 'torch'
            ImportName = 'torch'
        }
        @{
            Package = 'transformers'
            ImportName = 'transformers'
        }
    )

    OllamaModels = @(
        'llava'
    )

    PipInstallSequence = @(
        @{
            Arguments = @('install', '--upgrade', 'pip', 'setuptools', 'wheel')
        }
        @{
            Arguments = @('install', 'numpy==1.26.4', 'protobuf==3.20.2')
        }
        @{
            Arguments = @('install', 'paddlepaddle==2.6.2', 'paddleocr==2.7.3')
        }
        @{
            Arguments = @('install', 'torch', 'transformers', 'sentencepiece', 'ocrmypdf', 'nougat-ocr', 'easyocr')
        }
    )

    InteractiveOnlyDownloads = @(
        @{
            Name = 'Ghostscript'
            Commands = @('gswin64c')
            DownloadPage = 'https://ghostscript.com/releases/gsdnld.html'
            Notes = 'The official Windows installer no longer supports unattended silent installation. The wizard can open the official page or launch a downloaded installer, but the install step remains interactive.'
        }
    )
}
