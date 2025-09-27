module duende.codegen.dgen;

import duende.ast;
import duende.codegen.base;
import duende.codegen.d.types;
import duende.codegen.d.imports;
import duende.codegen.d.expressions;
import duende.codegen.d.statements;
import duende.codegen.d.matches;
import duende.codegen.d.helpers;
import std.format;
import std.array;
import std.string;
import std.conv;
import std.variant;
import std.range;

class DCodeGenerator : CodeGenerator {
    // Core state tracking
    private int indentLevel = 0;
    private bool hasMain = false;
    private string[string] frameTypes; // Track which types are frames (classes)
    private string[string] enumTypes;  // Track which types are enums
    private int matchCounter = 0; // Unique id for match temporaries
    private bool[string] requiredImports; // Track which imports are needed
    private DuendeType currentFunctionReturnType = DuendeType.VOID; // Track current function return type
    private DuendeType currentFunctionReturnInnerType = DuendeType.VOID; // Track inner type
    private string currentFunctionReturnCustomTypeName; // Track custom inner type name when returning generics
    private struct VarInfo { DuendeType type; string custom; DuendeType inner; string innerCustom; }
    private VarInfo[string] variableTypes; // Track variable types in current function scope
    // Optional function/method signature registry to support named-args reordering at call sites
    private Parameter[][string] functionSignatures; // name -> params
    private Parameter[][string] methodSignatures;   // Type.method -> params (future)
    // When emitting module-level globals, defer non-constant initializers to run inside main
    private struct DeferredInit { string name; string expr; int pos; }
    private DeferredInit[] deferredGlobalInits;
    private bool deferGlobalInitializersMode = false;
    private int currentStatementIndex = -1; // track position for ordered defers

    // Module/codegen context
    public string moduleName;         // e.g., "modules.testModule" or "imports"
    public string[] userModuleImports; // Pre-resolved D import lines for user modules (may include 'public ' and aliases)
    public string[] userAliasLines;    // Additional alias lines (e.g., symbol renames)
    public bool isLibraryModule = false; // If true, don't emit default main wrapper
    public bool includeStdMathHelpers = false; // Include Duende std.math helper wrappers

    // Mix in all the modular functionality
    mixin DTypeMixin;
    mixin DImportsMixin;
    mixin DExpressionsMixin;
    mixin DStatementsMixin;
    mixin DMatchesMixin;
    mixin DHelpersMixin;

    string generate(Program program) {
        auto result = appender!string();

        // Emit D module declaration if provided
        if (moduleName.length) {
            result ~= "module " ~ moduleName ~ ";\n\n";
        }

        // Pre-scan declarations to collect type information needed by expression codegen
        // so that calls like customer(...) for frames are emitted as `new customer(...)`
        // regardless of capitalization.
        foreach (stmt; program.statements) {
            if (auto fr = cast(FrameDeclaration)stmt) {
                frameTypes[fr.name] = fr.name;
            } else if (auto st = cast(StructDeclaration)stmt) {
                // If a struct declares @Implements, it is generated as a class; treat as frame for constructors
                if (st.annotations) {
                    foreach (ann; st.annotations) {
                        if (ann.name == "Implements" && ann.arguments.length > 0) {
                            frameTypes[st.name] = st.name;
                            break;
                        }
                    }
                }
            } else if (auto en = cast(EnumDeclaration)stmt) {
                enumTypes[en.name] = en.name;
            }
        }

        // Emit user module imports/aliases prior to std imports
        foreach (line; userModuleImports) {
            result ~= line ~ "\n";
        }
        foreach (line; userAliasLines) {
            result ~= line ~ "\n";
        }
        if ((userModuleImports.length + userAliasLines.length) > 0) {
            result ~= "\n";
        }

    // Reset import tracking
        requiredImports.clear();
        matchCounter = 0;

        // Analyze the program to determine required imports
        analyzeImports(program);

        // If std.math helpers requested, force needed imports
        if (includeStdMathHelpers) {
            requiredImports["std.math"] = true;
            requiredImports["std.format"] = true; // for formatFloat
        }

        // Generate imports based on analysis
        generateImports(result);

        // Generate helper functions only if needed
        if ("std.array" in requiredImports) {
            result ~= "struct DictEntry { string key; string value; }\n";
            result ~= "DictEntry[] duende_dict_items(string[string] dict) {\n";
            result ~= "    DictEntry[] result;\n";
            result ~= "    foreach (k, v; dict) {\n";
            result ~= "        result ~= DictEntry(k, v);\n";
            result ~= "    }\n";
            result ~= "    return result;\n";
            result ~= "}\n\n";
        }

        // Generate Result and Maybe types
        result ~= generateResultAndMaybeTypes();
        result ~= "\n";

        // Generate date/time helpers only if needed
        if ("std.datetime.systime" in requiredImports) {
            result ~= generateDateTimeHelpers();
            result ~= "\n";
        }

        // Generate system helpers (always safe to include when referenced)
        result ~= generateSystemHelpers();
        result ~= "\n";

        // Generate std.math helpers if requested
        if (includeStdMathHelpers) {
            result ~= generateStdMathHelpers();
            result ~= "\n";
        }

        // Helper to evaluate expression statements for values like Result/Maybe
        result ~= "void duende_eval(T)(T value) {\n";
        result ~= "    static if (__traits(hasMember, T, \"isOk\")) {\n";
        result ~= "        if (value.isOk) writeln(value.value); else writeln(value.errorMessage);\n";
        result ~= "    } else static if (__traits(hasMember, T, \"isSome\")) {\n";
        result ~= "        if (value.isSome) writeln(value.value); else {}\n";
        result ~= "    } else {\n";
        result ~= "        // No-op for other types; keep side-effects if any\n";
        result ~= "    }\n";
        result ~= "}\n\n";

        Statement[] nonFunctionStatements; // kept for potential future use (not used for main emission anymore)

        // First pass: collect function signatures and type info, and detect main
        foreach (stmt; program.statements) {
            if (auto funcDecl = cast(FunctionDeclaration)stmt) {
                if (funcDecl.name == "main") {
                    hasMain = true;
                }
                // Record function signatures for potential named-arg mapping
                functionSignatures[funcDecl.name] = funcDecl.parameters;
            }
        }

        // Emit global variable declarations at module level first (before functions that may use them)
        // Defer non-constant initializers into main when generating an entry module, preserving source order by recording positions
        deferGlobalInitializersMode = !isLibraryModule;
        foreach (i, stmt; program.statements) {
            currentStatementIndex = cast(int)i;
            if (cast(VariableDeclaration)stmt) {
                result ~= generateStatement(stmt);
                result ~= "\n";
            }
        }
        deferGlobalInitializersMode = false;
        currentStatementIndex = -1;

        // Second pass: emit type declarations and functions
        foreach (stmt; program.statements) {
            if (auto funcDecl = cast(FunctionDeclaration)stmt) {
                result ~= generateStatement(stmt);
                result ~= "\n";
            } else if (auto structDecl = cast(StructDeclaration)stmt) {
                result ~= generateStatement(stmt);
                result ~= "\n";
            } else if (auto frameDecl = cast(FrameDeclaration)stmt) {
                frameTypes[frameDecl.name] = frameDecl.name; // Track frame types
                result ~= generateStatement(stmt);
                result ~= "\n";
            } else if (auto enumDecl = cast(EnumDeclaration)stmt) {
                result ~= generateStatement(stmt);
                result ~= "\n";
            } else if (auto protocolDecl = cast(ProtocolDeclaration)stmt) {
                result ~= generateStatement(stmt);
                result ~= "\n";
            }
        }

        if (!hasMain && !isLibraryModule) {
            result ~= "\nvoid main(string[] __argv) {\n";
            indentLevel++;
            // Capture argv (excluding program name) for built-in args()
            result ~= indent() ~ "if (__argv.length > 1) DUENDE_ARGS = __argv[1 .. $]; else DUENDE_ARGS = [];\n";
            // Perform deferred global initializations interleaved with other top-level statements in source order
            foreach (i, stmt; program.statements) {
                // For variable declarations: emit only the deferred assignment (if any)
                if (auto vd = cast(VariableDeclaration)stmt) {
                    // Find deferred init by variable name and emit here
                    size_t idx = size_t.max;
                    foreach (j, di; deferredGlobalInits) {
                        if (di.name == vd.name) { idx = j; break; }
                    }
                    if (idx != size_t.max) {
                        auto di = deferredGlobalInits[idx];
                        result ~= indent() ~ di.name ~ " = " ~ di.expr ~ ";\n";
                        // remove it so we don't emit twice
                        deferredGlobalInits = deferredGlobalInits[0 .. idx] ~ deferredGlobalInits[idx+1 .. $];
                    }
                } else if (!(cast(StructDeclaration)stmt || cast(FrameDeclaration)stmt || 
                             cast(EnumDeclaration)stmt || cast(ProtocolDeclaration)stmt ||
                             cast(FunctionDeclaration)stmt)) {
                    // Non-declaration top-level statements execute in main in order
                    result ~= generateStatement(stmt);
                }
            }
            // Clear any remaining deferred (should not happen)
            deferredGlobalInits.length = 0;
            indentLevel--;
            result ~= "}\n";
        }

        return result.data;
    }

    private string indent() {
        return "    ".replicate(indentLevel);
    }

    /**
     * Check if an expression can be evaluated at compile time.
     * Only simple literals and basic operations should be treated as compile-time constants.
     */
    private bool isCompileTimeConstant(Expression expr) {
        if (!expr) return true; // null initializer is compile-time constant (default value)
        
        // Literal expressions are compile-time constants
        if (cast(LiteralExpression)expr) {
            return true;
        }
        
        // Bytes literals are compile-time constants
        if (cast(BytesLiteralExpression)expr) {
            return true;
        }
        
        // List literals are compile-time constant if all elements are
        if (auto listExpr = cast(ListLiteralExpression)expr) {
            foreach (elem; listExpr.elements) {
                if (!isCompileTimeConstant(elem)) {
                    return false;
                }
            }
            return true;
        }
        
        // Dict literals are compile-time constant if all keys and values are
        if (auto dictExpr = cast(DictLiteralExpression)expr) {
            foreach (key; dictExpr.keys) {
                if (!isCompileTimeConstant(key)) {
                    return false;
                }
            }
            foreach (value; dictExpr.values) {
                if (!isCompileTimeConstant(value)) {
                    return false;
                }
            }
            return true;
        }
        
        // Binary expressions with compile-time constant operands
        if (auto binExpr = cast(BinaryExpression)expr) {
            return isCompileTimeConstant(binExpr.left) && isCompileTimeConstant(binExpr.right);
        }
        
        // Unary expressions with compile-time constant operands
        if (auto unaryExpr = cast(UnaryExpression)expr) {
            return isCompileTimeConstant(unaryExpr.operand);
        }
        
        // Variables that refer to other compile-time constants (basic case)
        if (auto varExpr = cast(VariableExpression)expr) {
            // For simplicity, we'll be conservative and only allow references to known global constants
            // A more sophisticated implementation could track which variables are compile-time constants
            return false;
        }
        
        // Function calls, method calls, and other complex expressions are not compile-time constants
        return false;
    }
}