# Duende Programming Language

<p align="center">
  <img src="duende-logo.svg" alt="Duende Logo" width="200"/>
</p>

Duende is a modern programming language with a focus on being fun to use.
Made to feel like a scripting language, but with the assurances of static typing and speed of native binaries.
Duende is automatically transpiled to D and compiled with your favorite D compiler.

It was born from my desire to have something that felt like a scripting language, but with some of the guard-rails of static types and the speed of native compilation.

The language just tries to stay out of your way to allow you to do things, you will not find any "purity" here, OOP, Functional...if something is useful we borrow it.
This means that no decisions here were taken with some grand theoretical justification, don't overthink why something is the way it is, it just is because I found it to be useful and/or fun, that's it.

As many things were molded to my liking, it means that if you disagree, you are probably wrong ;)

Duende is still in its infancy and I do not recommend you to use it for anything too important, right now it has a lot of code surface that was not thoroughly tested that being said PRs are welcome, and if you want to help, please reach out.


```duende

// Match an email with a regex
let string email = "test@email.com"
match email do
	regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$") -> print("This looks like an email")
	_ -> print("This does not look like an email")
end

// Classify numbers with pattern matching and guards
string classify(int n) do
	return match n do
		0        -> "zero"
		_ if n < 0 -> "negative"
		_        -> "positive"
	end
end

// Safe division using Results and the ? else operator
Result<float> safe_div(int a, int b) do
	if b == 0 do return Error("division by zero") end
	return Ok(a / b)
end

int main() do
	// Simple range and print
	for i in 1..5 do
		print("i=${i} => " + classify(i))
	end

	let Result<int> value = safe_div(10, 0) ? else -1.0
	print("safe_div result=${value}")
end
```

### Primitive Types
	Duende int → D long: Duende's 64-bit integers map naturally to D's long type (Duende type name is 'int')
	Duende float → D double: Duende's double-precision floats map to D's double type
	Duende string → D string: D's built-in UTF-8 strings provide excellent compatibility
	Duende bool → D bool: Direct mapping with identical semantics
	Duende bytes → D ubyte[]: Dynamic arrays provide the same functionality
	Duende auto → D auto: Type inference

### Variable Declarations
	var (mutable) → D mutable: Duende's var creates mutable variables as standard D variables
	let (immutable) → D immutable: Duende's let creates immutable bindings using D's immutable keyword
	const → D enum: Duende's const creates compile-time immutable values represented by D's enum
	
### Control Flow
	```
	if/elif/else - `if (condition) do ... elif ... else ... end`
	while - `while (condition) do ... end`
	for - For loops are used with ranges that can be ascending or descending and can have steps, the step can be ommitted and it will be 1.
		
		for i in 1..5 do
			print(i)
		end
		
		This will print: 1, 2, 3, 4 and 5
		
		for i in 1..5 step 2 do
			print(1)
		end
		
		This will print: 1, 3, 5
	```
	
### Pattern Matching
```
    let string email = "test@email.com"
    match email do
        regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$") -> print("This looks like an email")
        _ -> print("This does not look like an email")
    end
    
	var list<int> numbers = [1, 2, 3, 4, 5]
    match 1 do
        numbers[0] -> print("First number is 1")
        _ -> print("This should not print")
    end

    var dict colors = {"red": "stop", "green": "go", "yellow": "caution"}
    match colors["red"] do
        "stop" -> print("Stop the car")
        "go" -> print("Go ahead")
        _ -> print("Unknown signal")
    end
```

## Collection Types
- **Duende list → D dynamic arrays (T[])**: D's built-in dynamic arrays are garbage collected and provide similar functionality
- **Duende dict → D associative arrays (V[K])**: Built-in associative arrays with hash table implementation
- **Collection methods**: Implement as UFCS (Uniform Function Call Syntax) functions in standard library

## IDE Support
For syntax highlighting you can check the `tools` folder, there are definitions for:
- VSCode
- Kate
- Nano

If your favorite editor is missing, please open an issue or a PR.

## Agents and AI
This was my first D project and a lot of the code was written with the help of AI (60% to 70% if I had to guess), so if you want to use AI to contribute to the project feel free to do it, just review it and and make the sure that all tests are green.


## Building and Using the Duende Compiler

The Duende compiler is written in D and transpiles Duende source code to D, which is then compiled to native binaries.

### Prerequisites
- D compiler (`dmd`)
- `dub` (D package manager)
- `uv` (for running the test suite)

### Building the Compiler
```bash
# Clone the repository and build the compiler
dub build

# Run the test suite to verify everything works
./test.sh
```

### Using the Compiler
```bash
# Compile a Duende source file
./duende examples/variables.du

# Compile and run immediately
./duende examples/variables.du -r

# Compile with verbose output to see generated D code
./duende examples/variables.du -v

# Compile, run, and show verbose output
./duende examples/variables.du -r -v

# Choose the D compiler (dmd by default, or ldc)
./duende examples/variables.du --compiler ldc

# Specify custom output file
./duende examples/variables.du -o my_program

# Run the compiled executable manually
./examples/duende_build/variables
```

### Compiler Options
- `-v, --verbose`: Show verbose compilation output including generated D code
- `-r, --run`: Compile and run the executable immediately
- `-o, --output`: Specify output file name or directory
	- `-o .` places the executable alongside the `duende` compiler binary
	- `-o <dir>` (absolute or relative path) places the executable in that directory
	- `-o <name>` writes `<name>` inside the default build dir next to your source
- `--compiler <dmd|ldc>`: Select which D compiler to use (defaults to `dmd`)
- `--emit-d`: Generate D source files and print module mappings, then exit (no compilation)
- `--ast`: Print AST and exit (for debugging)
- `--tokens`: Print tokens and exit (for debugging)
- `--help`: Show help message

### Example Commands

**Development workflow with --emit-d:**
```bash
# Generate D code and inspect mappings without compilation
./duende examples/basic_arithmetic.du --emit-d

# Output shows module to D file mappings:
# basic_arithmetic => /path/to/examples/duende_build/basic_arithmetic.d
```


### Examples
All examples in the `examples/` directory demonstrate different language features and can be compiled and run:

```bash
# Try different examples (compile and run)
./duende examples/basic_arithmetic.du -r
./duende examples/functions.du -r
./duende examples/control_flow.du -r

# Interactive input example
./duende examples/input.du -r

# Or compile manually then run
./duende examples/basic_arithmetic.du && ./examples/duende_build/basic_arithmetic
```

The compiler automatically:
- Detects and uses `dub.sdl`/`dub.json` files for dependency management
- Produces native executables through the D compiler


## License
Duende is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
