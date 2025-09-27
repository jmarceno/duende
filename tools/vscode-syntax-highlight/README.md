# Duende Language Support for VS Code

This extension provides comprehensive syntax highlighting for the Duende programming language with rich color differentiation.

## Features

- **Enhanced Syntax Highlighting** for `.du` and `.duende` files with distinct colors for:

### Keywords & Control Flow
- **Control Keywords**: `if`, `else`, `while`, `for`, `in`, `match`, `return`, `break`, `continue`, `defer` (distinct color)
- **Declaration Keywords**: `struct`, `enum`, `frame`, `protocol`, `let`, `var` (different color)
- **Import Keywords**: `import` (separate color)
- **Block Keywords**: `do`, `end` (special highlighting)

### Types & Data
- **Primitive Types**: `int`, `string`, `bool`, `void` (one color)
- **Collection Types**: `list`, `dict` (different color)
- **DateTime Types**: `date`, `time`, `datetime` (distinct color)
- **User Types**: `Person`, `Status` (capitalized types get special color)

### Functions & Identifiers
- **Function Calls**: Function names when called (different shade)
- **Built-in Functions**: `print`, `error`, `debug` (distinct color)
- **Method Calls**: `user.getName()` (function call color)
- **Property Access**: `user.name` (property color)

### Variables & Constants
- **Parameters**: Function parameter names (special color)
- **Variables**: Regular variable names (standard color)
- **Constants**: `UPPER_CASE` variables (constant color)
- **Fields**: Object properties (property color)

### Special Features
- **Annotations**: `@...` (decorator color)
- **String Interpolation**: `"Hello ${name}"` (expression highlighting)
- **Bytes Literals**: `b"data"` (special string color)

## Supported File Extensions

- `.du` - Standard Duende source files
- `.duende` - Alternative Duende source files

## Language Features Highlighted

### Keywords
- Complete list (exhaustive):
	`auto`, `bool`, `break`, `bytes`, `continue`, `defer`, `dict`, `do`, `else`, `end`, `enum`, `Error`, `false`, `float`, `for`, `frame`, `if`, `import`, `in`, `int`, `let`, `list`, `match`, `Maybe`, `Ok`, `protocol`, `Result`, `return`, `Some`, `string`, `struct`, `this`, `true`, `var`, `void`, `while`, `? else`

### Data Types
- Primitives: `auto`, `int`, `float`, `string`, `bool`, `void`, `bytes`
- Collections: `list`, `dict`

### Special Features
- Function declarations with return type annotations
- String interpolation highlighting in `"${expression}"` format
- Bytes literals with `b"..."` syntax
- Triple-quoted multiline strings

## Installation

1. Install the extension from the VS Code marketplace
2. Open any `.du` or `.duende` file to see syntax highlighting

## Contributing

This extension is part of the Duende compiler project. Please report issues or contribute improvements through the main repository.

## License

Same as the Duende compiler project.