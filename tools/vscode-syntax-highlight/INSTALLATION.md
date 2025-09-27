# Installation Guide for Duende VS Code Extension

## Prerequisites

- Visual Studio Code 1.60.0 or higher
- Duende language files (`.du` or `.duende`)

## Installation Methods

### Method 1: From VS Code Marketplace (Recommended)
1. Open Visual Studio Code
2. Go to Extensions view (Ctrl+Shift+X)
3. Search for "Duende Language Support"
4. Click Install

### Method 2: Install from VSIX Package
1. Download the `.vsix` file from releases
2. Open VS Code
3. Go to Extensions view (Ctrl+Shift+X)
4. Click on the "..." menu at the top
5. Select "Install from VSIX..."
6. Choose the downloaded `.vsix` file

### Method 3: Development Installation
1. Clone the repository
2. Navigate to the `duende-code-highlight` folder
3. Run `npm install` (if there are any dependencies)
4. Press F5 to launch a new Extension Development Host window
5. Open a `.du` or `.duende` file to test syntax highlighting

## Building the Extension

To package the extension for distribution:

```bash
# Install vsce (Visual Studio Code Extension CLI)
npm install -g vsce

# Package the extension
cd duende-code-highlight
vsce package

# This will create a .vsix file that can be installed
```

## Usage

Once installed, the extension will automatically provide syntax highlighting for:

- Files with `.du` extension
- Files with `.duende` extension

The highlighting includes:

- **Keywords** (exhaustive): `auto`, `bool`, `break`, `bytes`, `continue`, `defer`, `dict`, `do`, `else`, `end`, `enum`, `Error`, `false`, `float`, `for`, `frame`, `if`, `import`, `in`, `int`, `let`, `list`, `match`, `Maybe`, `Ok`, `protocol`, `Result`, `return`, `Some`, `string`, `struct`, `this`, `true`, `var`, `void`, `while`, `? else`
- **Data Types**: `auto`, `int`, `float`, `string`, `bool`, `bytes`, `list`, `dict`, `void`
- **Function Names**: Highlighted in function calls
- **Comments**: Line comments starting with `//`
- **Strings**: Including string interpolation `${...}`
- **Numbers**: Integer and float literals
- **Operators**: Arithmetic, comparison, logical, range, and the `? else` operator

## Troubleshooting

### Extension Not Working
1. Verify VS Code version (1.60.0+)
2. Restart VS Code
3. Check the file extension is `.du` or `.duende`

### No Syntax Highlighting
1. Ensure the file is detected as Duende language
2. Check the language mode in the status bar
3. Manually set language to "Duende" if needed

### Contributing
To contribute improvements to the syntax highlighting:

1. Fork the repository
2. Make changes to `syntaxes/duende.tmLanguage.json`
3. Test with various Duende code samples
4. Submit a pull request

## License

This extension follows the same license as the Duende compiler project.