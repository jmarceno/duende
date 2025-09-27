module duende.codegen.d.statements;

import duende.ast;
import std.array;
import std.string;
import std.conv;

/**
 * Statement generation for D code.
 * This module handles all types of statements: variable declarations,
 * function declarations, control flow, struct/frame/enum declarations, etc.
 */
mixin template DStatementsMixin() {
    /**
     * Generate D code for any statement.
     * This is the main entry point for statement generation.
     */
    string generateStatement(Statement stmt) {
        if (auto varDecl = cast(VariableDeclaration)stmt) {
            return generateVariableDeclaration(varDecl);
        }
        if (auto funcDecl = cast(FunctionDeclaration)stmt) {
            return generateFunctionDeclaration(funcDecl);
        }
        if (auto structDecl = cast(StructDeclaration)stmt) {
            return generateStructDeclaration(structDecl);
        }
        if (auto frameDecl = cast(FrameDeclaration)stmt) {
            return generateFrameDeclaration(frameDecl);
        }
        if (auto enumDecl = cast(EnumDeclaration)stmt) {
            return generateEnumDeclaration(enumDecl);
        }
        if (auto protocolDecl = cast(ProtocolDeclaration)stmt) {
            return generateProtocolDeclaration(protocolDecl);
        }
        if (auto methodDecl = cast(MethodDeclaration)stmt) {
            return generateMethodDeclaration(methodDecl);
        }
        if (auto matchStmt = cast(MatchStatement)stmt) {
            return generateMatchStatement(matchStmt);
        }
        if (auto exprStmt = cast(ExpressionStatement)stmt) {
            string e = generateExpression(exprStmt.expression);
            // Suppress auto-print for side-effect-only builtins
            bool suppressPrint = false;
            if (auto call = cast(CallExpression)exprStmt.expression) {
                immutable suppressNames = [
                    "writeText", "writeBytes", "appendText", "appendBytes",
                    "writeLines", "appendLines", "deleteFile", "makeDir",
                    "removeDir"
                ];
                foreach (name; suppressNames) {
                    if (call.name == name) { suppressPrint = true; break; }
                }
            }
            if (suppressPrint) {
                return indent() ~ e ~ ";\n";
            }
            return indent() ~ "(() { static if (is(typeof(" ~ e ~ ") == void)) { " ~ e ~ "; } else { auto __du_tmp = " ~ e ~ "; duende_eval(__du_tmp); } })();\n";
        }
        if (auto retStmt = cast(ReturnStatement)stmt) {
            return generateReturnStatement(retStmt);
        }
        if (auto ifStmt = cast(IfStatement)stmt) {
            return generateIfStatement(ifStmt);
        }
        if (auto forStmt = cast(ForStatement)stmt) {
            return generateForStatement(forStmt);
        }
        if (auto forInStmt = cast(ForInStatement)stmt) {
            return generateForInStatement(forInStmt);
        }
        if (auto whileStmt = cast(WhileStatement)stmt) {
            return generateWhileStatement(whileStmt);
        }
        if (cast(BreakStatement)stmt) {
            return indent() ~ "break;\n";
        }
        if (cast(ContinueStatement)stmt) {
            return indent() ~ "continue;\n";
        }
        if (auto deferStmt = cast(DeferStatement)stmt) {
            return generateDeferStatement(deferStmt);
        }

        return "";
    }

    /**
     * Generate variable declarations with proper type handling.
     */
    private string generateVariableDeclaration(VariableDeclaration varDecl) {
        // Detect if we are emitting at module scope (globals pass) using the deferral mode flag,
        // which is enabled only during the top-level globals emission phase.
        bool atModuleScope = deferGlobalInitializersMode || varDecl.isGlobal;
        // Global variables should not be indented for cleanliness
        string result = atModuleScope ? "" : indent();

        string custom = varDecl.innerCustomTypeName.length ? varDecl.innerCustomTypeName : varDecl.customTypeName;

        // Determine declared type, with a safety fallback to 'auto' to avoid invalid Result!(auto)/Maybe!(auto)
        string declaredType = toDType(varDecl.type, custom, varDecl.innerType);
        bool needsAutoFallback =
            (varDecl.type == DuendeType.RESULT || varDecl.type == DuendeType.MAYBE) &&
            varDecl.innerType == DuendeType.CUSTOM &&
            (!custom.length);

        if (needsAutoFallback) {
            declaredType = "auto";
        }

        // Precompute initializer expression if present, since we may need its typeof for deferred globals
        string initExpr;
        const bool hasInitializer = (varDecl.initializer !is null);
    if (hasInitializer) {
            // Special handling for bytes literals
            if (varDecl.type == DuendeType.BYTES && cast(ListLiteralExpression)varDecl.initializer !is null) {
                auto listExpr = cast(ListLiteralExpression)varDecl.initializer;
                initExpr = generateBytesLiteralFromList(listExpr);
            } else if (varDecl.type == DuendeType.LIST && cast(ListLiteralExpression)varDecl.initializer !is null) {
                auto listExpr = cast(ListLiteralExpression)varDecl.initializer;
                // If generic element type is provided, honor it for empty initialization
                if (listExpr.elements.length == 0) {
                    // Compute element D type
                    string elem;
                    if (varDecl.innerType == DuendeType.CUSTOM) {
                        elem = (varDecl.innerCustomTypeName.length ? varDecl.innerCustomTypeName : varDecl.customTypeName);
                    } else {
                        elem = toDTypeSimple(varDecl.innerType);
                    }
                    if (!elem.length || elem == "auto") elem = "string"; // fallback
                    initExpr = "(" ~ elem ~ "[]).init";
                } else if (varDecl.innerType == DuendeType.VOID) {
                    // Legacy untyped list: coerce elements to string to match string[] default
                    auto buf = appender!string();
                    buf ~= "[";
                    foreach (i, element; listExpr.elements) {
                        if (i > 0) buf ~= ", ";
                        buf ~= generateExpression(element) ~ ".to!string";
                    }
                    buf ~= "]";
                    initExpr = buf.data;
                } else {
                    // Typed list with elements: emit raw elements and let D type-check
                    initExpr = generateExpression(varDecl.initializer);
                }
            } else {
                initExpr = generateExpression(varDecl.initializer);
            }

            if (varDecl.type == DuendeType.STRING &&
                cast(ListLiteralExpression)varDecl.initializer is null &&
                cast(DictLiteralExpression)varDecl.initializer is null &&
                cast(PropertyExpression)varDecl.initializer is null &&
                cast(IndexExpression)varDecl.initializer is null &&
                cast(LiteralExpression)varDecl.initializer is null) { // Don't convert string literals
                initExpr ~= ".to!string";
            }

            if (varDecl.type == DuendeType.INT && cast(IndexExpression)varDecl.initializer !is null) {
                initExpr ~= ".to!long";
            }

            if (varDecl.type == DuendeType.INT && cast(PropertyExpression)varDecl.initializer !is null) {
                auto propExpr = cast(PropertyExpression)varDecl.initializer;
                if (propExpr.property == "first" || propExpr.property == "last") {
                    initExpr = "(" ~ initExpr ~ ").to!long";
                }
            }

            // Qualify enum member on initialization when declaring an enum-typed variable
            if ((varDecl.type == DuendeType.ENUM || varDecl.type == DuendeType.CUSTOM) && custom.length && cast(VariableExpression)varDecl.initializer !is null) {
                if (auto _ = custom in enumTypes) {
                    if (initExpr.indexOf('.') == -1) {
                        initExpr = custom ~ "." ~ initExpr;
                    }
                }
            }

            // For bytes, ensure variable storage is mutable ubyte[]; provider helpers often return immutable
            if (varDecl.type == DuendeType.BYTES) {
                // If initializer may yield immutable(ubyte)[], cast and dup to mutable
                initExpr = "cast(ubyte[])(" ~ initExpr ~ ").dup";
            }
        }

        // Decide if we can/should defer initialization to main
    bool canDefer = hasInitializer && atModuleScope && deferGlobalInitializersMode && !isCompileTimeConstant(varDecl.initializer);

        // If we are at module scope and plan to defer a non-constant initializer,
        // force mutable declaration (immutable cannot be assigned later) and avoid 'immutable'.
        if (canDefer || varDecl.isMutable || varDecl.type == DuendeType.AUTO) {
            // For auto with deferred init, use typeof(init) to allow declaration without initializer
            if (canDefer && varDecl.type == DuendeType.AUTO) {
                result ~= "typeof(" ~ initExpr ~ ") " ~ varDecl.name;
            } else {
                result ~= declaredType ~ " " ~ varDecl.name;
            }
        } else {
            // For list/dict, avoid immutable since many expressions yield mutable arrays
            if (varDecl.type == DuendeType.LIST || varDecl.type == DuendeType.DICT) {
                result ~= declaredType ~ " " ~ varDecl.name;
            } else {
                result ~= "immutable " ~ declaredType ~ " " ~ varDecl.name;
            }
        }

        if (hasInitializer) {
            if (canDefer) {
                string rhs = initExpr;
                // For bytes, ensure we initialize with a mutable copy at runtime
                if (varDecl.type == DuendeType.BYTES) {
                    rhs = "cast(ubyte[])(" ~ rhs ~ ").dup";
                }
                deferredGlobalInits ~= DeferredInit(varDecl.name, rhs, currentStatementIndex);
            } else {
                result ~= " = " ~ initExpr;
            }
        }

        // Track variable type for later enum/date handling and regex usage
        DuendeType trackedType = varDecl.type;
        if (varDecl.initializer) {
            if (cast(RegexLiteralExpression)varDecl.initializer !is null) {
                trackedType = DuendeType.REGEX;
            } else if (auto initCall = cast(CallExpression)varDecl.initializer) {
                if (initCall.name == "regex") {
                    trackedType = DuendeType.REGEX;
                }
                // Identify date/time-producing calls
                if (isDateConstructorCall(initCall) || initCall.name == "toUTC" || initCall.name == "toLocal" || initCall.name == "toTZ" || initCall.name == "addDays" || initCall.name == "addHours" || initCall.name == "addMinutes" || initCall.name == "addSeconds") {
                    trackedType = DuendeType.DATE;
                }
            } else if (cast(BytesLiteralExpression)varDecl.initializer !is null) {
                trackedType = DuendeType.BYTES;
            } else if (auto m = cast(MethodCallExpression)varDecl.initializer) {
                if (m.method == "toBytes") trackedType = DuendeType.BYTES;
            }
        }
        variableTypes[varDecl.name] = VarInfo(trackedType, custom, varDecl.innerType, varDecl.innerCustomTypeName);

        return result ~ ";\n";
    }

    /**
     * Generate function declarations with proper signatures and bodies.
     */
    private string generateFunctionDeclaration(FunctionDeclaration funcDecl) {
        auto result = appender!string();
        string returnType = toDType(funcDecl.returnType, funcDecl.returnCustomTypeName, funcDecl.returnInnerType);

        // Set current function context for error generation
        currentFunctionReturnType = funcDecl.returnType;
        currentFunctionReturnInnerType = funcDecl.returnInnerType;
        currentFunctionReturnCustomTypeName = funcDecl.returnCustomTypeName;

        // Avoid emitting invalid Result!(auto)/Maybe!(auto) in signatures; fall back to 'auto'
        if ((funcDecl.returnType == DuendeType.RESULT || funcDecl.returnType == DuendeType.MAYBE) &&
            funcDecl.returnInnerType == DuendeType.CUSTOM &&
            (!funcDecl.returnCustomTypeName.length)) {
            returnType = "auto";
        }

        if (funcDecl.name == "main" && funcDecl.returnType == DuendeType.INT) {
            returnType = "int";
        }

        // If any parameter is 'auto', lift to a D template with concrete type params (T0, T1, ...)
        string[] templateTypeParams;
        string[string] autoParamToTemplate; // paramName -> Tn
        foreach (i, param; funcDecl.parameters) {
            if (param.type == DuendeType.AUTO) {
                string tname = "T" ~ to!string(i);
                templateTypeParams ~= tname;
                autoParamToTemplate[param.name] = tname;
            }
        }

        // Emit function name, optionally with template parameter list
        result ~= indent() ~ returnType ~ " " ~ funcDecl.name;
        if (templateTypeParams.length > 0) {
            result ~= "(" ~ templateTypeParams.join(", ") ~ ")";
        }
        result ~= "(";

        foreach (i, param; funcDecl.parameters) {
            if (i > 0) result ~= ", ";
            string pType;
            if (param.type == DuendeType.AUTO) {
                // Use the corresponding template type parameter instead of 'auto'
                pType = autoParamToTemplate[param.name];
            } else {
                pType = toDType(param.type, param.customTypeName, param.innerType);
            }
            result ~= pType ~ " " ~ param.name;
            if (param.defaultValue !is null) {
                result ~= " = " ~ generateExpression(param.defaultValue);
            }
        }

        result ~= ") {\n";
        indentLevel++;

        // Reset variable type tracking for this function scope
        variableTypes = null;

        // If this is the entry main, run any deferred global initializers first
        if (funcDecl.name == "main" && deferredGlobalInits.length > 0) {
            foreach (di; deferredGlobalInits) {
                result ~= indent() ~ di.name ~ " = " ~ di.expr ~ ";\n";
            }
            // Clear to avoid emitting again in autogenerated main path
            deferredGlobalInits.length = 0;
        }

        foreach (stmt; funcDecl.body) {
            result ~= generateStatement(stmt);
        }

        // Add implicit return 0 for main function that returns int
        if (funcDecl.name == "main" && funcDecl.returnType == DuendeType.INT) {
            bool hasReturnStatement = false;
            foreach (stmt; funcDecl.body) {
                if (cast(ReturnStatement)stmt) {
                    hasReturnStatement = true;
                    break;
                }
            }
            if (!hasReturnStatement) {
                result ~= indent() ~ "return 0;\n";
            }
        }

        indentLevel--;
        result ~= indent() ~ "}\n";

        // Reset function context
        currentFunctionReturnType = DuendeType.VOID;
        currentFunctionReturnInnerType = DuendeType.VOID;
        currentFunctionReturnCustomTypeName = null;

        return result.data;
    }

    /**
     * Generate return statements.
     */
    private string generateReturnStatement(ReturnStatement retStmt) {
        if (retStmt.value) {
            return indent() ~ "return " ~ generateExpression(retStmt.value) ~ ";\n";
        }
        return indent() ~ "return;\n";
    }

    /**
     * Generate defer statements (scope(exit) in D).
     */
    private string generateDeferStatement(DeferStatement deferStmt) {
        return indent() ~ "scope(exit) " ~ generateExpression(deferStmt.call) ~ ";\n";
    }

    /**
     * Generate if statements with optional else branches.
     */
    private string generateIfStatement(IfStatement ifStmt) {
        auto result = appender!string();
        result ~= indent() ~ "if (" ~ generateExpression(ifStmt.condition) ~ ") {\n";

        indentLevel++;
        foreach (stmt; ifStmt.thenBranch) {
            result ~= generateStatement(stmt);
        }
        indentLevel--;

        // Generate elif clauses
        foreach (elifClause; ifStmt.elifClauses) {
            result ~= indent() ~ "} else if (" ~ generateExpression(elifClause.condition) ~ ") {\n";
            indentLevel++;
            foreach (stmt; elifClause.body) {
                result ~= generateStatement(stmt);
            }
            indentLevel--;
        }

        if (ifStmt.elseBranch && ifStmt.elseBranch.length > 0) {
            result ~= indent() ~ "} else {\n";
            indentLevel++;
            foreach (stmt; ifStmt.elseBranch) {
                result ~= generateStatement(stmt);
            }
            indentLevel--;
        }

        result ~= indent() ~ "}\n";
        return result.data;
    }

    /**
     * Generate for statements (range-based loops).
     */
    private string generateForStatement(ForStatement forStmt) {
        auto result = appender!string();
        result ~= indent() ~ "foreach (" ~ forStmt.variable ~ "; " ~
                  generateExpression(forStmt.start) ~ " .. " ~
                  generateExpression(forStmt.end) ~ " + 1) {\n";

        indentLevel++;
        foreach (stmt; forStmt.body) {
            result ~= generateStatement(stmt);
        }
        indentLevel--;

        result ~= indent() ~ "}\n";
        return result.data;
    }

    /**
     * Generate for-in statements (foreach in D).
     */
    private string generateForInStatement(ForInStatement forInStmt) {
        auto result = appender!string();
        result ~= indent() ~ "foreach (" ~ forInStmt.variable ~ "; " ~
                  generateExpression(forInStmt.iterable) ~ ") {\n";

        indentLevel++;
        foreach (stmt; forInStmt.body) {
            result ~= generateStatement(stmt);
        }
        indentLevel--;

        result ~= indent() ~ "}\n";
        return result.data;
    }

    /**
     * Generate while statements.
     */
    private string generateWhileStatement(WhileStatement whileStmt) {
        auto result = appender!string();
        result ~= indent() ~ "while (" ~ generateExpression(whileStmt.condition) ~ ") {\n";

        indentLevel++;
        foreach (stmt; whileStmt.body) {
            result ~= generateStatement(stmt);
        }
        indentLevel--;

        result ~= indent() ~ "}\n";
        return result.data;
    }

    /**
     * Generate struct declarations.
     * Handles both plain structs and protocol-implementing structs.
     */
    private string generateStructDeclaration(StructDeclaration structDecl) {
        auto result = appender!string();

        // For structs implementing protocols, we need to generate a class wrapper
        string[] interfaces;
        if (structDecl.annotations) {
            foreach (annotation; structDecl.annotations) {
                if (annotation.name == "Implements" && annotation.arguments.length > 0) {
                    interfaces ~= annotation.arguments;
                }
            }
        }

        if (interfaces.length > 0) {
            // Generate as a class for interface implementation
            frameTypes[structDecl.name] = structDecl.name; // Track as frame type since it's generated as class
            result ~= "class " ~ structDecl.name;
            result ~= " : ";
            foreach (i, iface; interfaces) {
                if (i > 0) result ~= ", ";
                result ~= iface;
            }
            result ~= " {\n";
        } else {
            result ~= "struct " ~ structDecl.name ~ " {\n";
        }
        indentLevel++;

        // Generate immutable fields
        foreach (field; structDecl.fields) {
            result ~= indent() ~ "immutable " ~ toDType(field.type, field.customTypeName) ~ " " ~ field.name ~ ";\n";
        }

        // Generate constructor
        if (structDecl.fields.length > 0) {
            result ~= "\n" ~ indent() ~ "this(";
            foreach (i, field; structDecl.fields) {
                if (i > 0) result ~= ", ";
                result ~= toDType(field.type, field.customTypeName) ~ " " ~ field.name;
            }
            result ~= ") {\n";
            indentLevel++;
            foreach (field; structDecl.fields) {
                result ~= indent() ~ "this." ~ field.name ~ " = " ~ field.name ~ ";\n";
            }
            indentLevel--;
            result ~= indent() ~ "}\n";
        }

        // Generate methods
        foreach (method; structDecl.methods) {
            result ~= "\n";
            result ~= generateMethodDeclaration(method, true); // true = for struct (const methods)
        }

        // Generate default implementations from protocols via mixins
        if (structDecl.annotations) {
            foreach (annotation; structDecl.annotations) {
                if (annotation.name == "Implements" && annotation.arguments.length > 0) {
                    foreach (protocolName; annotation.arguments) {
                        result ~= "\n" ~ indent() ~ "mixin " ~ protocolName ~ "_DefaultImpls;\n";
                    }
                }
            }
        }

        indentLevel--;
        result ~= "}\n";
        return result.data;
    }

    /**
     * Generate frame declarations (classes in D).
     */
    private string generateFrameDeclaration(FrameDeclaration frameDecl) {
        auto result = appender!string();
        frameTypes[frameDecl.name] = frameDecl.name; // Track frame types for constructor generation
        result ~= "class " ~ frameDecl.name;

        // Add interface implementations from @Implements annotations
        string[] interfaces;
        if (frameDecl.annotations) {
            foreach (annotation; frameDecl.annotations) {
                if (annotation.name == "Implements" && annotation.arguments.length > 0) {
                    interfaces ~= annotation.arguments;
                }
            }
        }

        if (interfaces.length > 0) {
            result ~= " : ";
            foreach (i, iface; interfaces) {
                if (i > 0) result ~= ", ";
                result ~= iface;
            }
        }

        result ~= " {\n";
        indentLevel++;

        // Generate fields
        foreach (field; frameDecl.fields) {
            if (field.isMutable) {
                result ~= indent() ~ toDType(field.type, field.customTypeName) ~ " " ~ field.name ~ ";\n";
            } else {
                result ~= indent() ~ "immutable " ~ toDType(field.type, field.customTypeName) ~ " " ~ field.name ~ ";\n";
            }
        }

        // Generate constructor
        if (frameDecl.fields.length > 0) {
            result ~= "\n" ~ indent() ~ "this(";
            foreach (i, field; frameDecl.fields) {
                if (i > 0) result ~= ", ";
                result ~= toDType(field.type, field.customTypeName) ~ " " ~ field.name;
            }
            result ~= ") {\n";
            indentLevel++;
            foreach (field; frameDecl.fields) {
                result ~= indent() ~ "this." ~ field.name ~ " = " ~ field.name ~ ";\n";
            }
            indentLevel--;
            result ~= indent() ~ "}\n";
        }

        // Generate methods
        foreach (method; frameDecl.methods) {
            result ~= "\n";
            result ~= generateMethodDeclaration(method, false); // false = for frame (non-const methods)
        }

        // Generate default implementations from protocols via mixins
        if (frameDecl.annotations) {
            foreach (annotation; frameDecl.annotations) {
                if (annotation.name == "Implements" && annotation.arguments.length > 0) {
                    foreach (protocolName; annotation.arguments) {
                        result ~= "\n" ~ indent() ~ "mixin " ~ protocolName ~ "_DefaultImpls;\n";
                    }
                }
            }
        }

        indentLevel--;
        result ~= "}\n";
        return result.data;
    }

    /**
     * Generate enum declarations.
     */
    private string generateEnumDeclaration(EnumDeclaration enumDecl) {
        auto result = appender!string();
        result ~= "enum " ~ enumDecl.name ~ " {\n";
        indentLevel++;

        // Track enum type name so we can qualify member names when needed
        enumTypes[enumDecl.name] = enumDecl.name;

        foreach (i, value; enumDecl.values) {
            result ~= indent() ~ value;
            if (i + 1 < enumDecl.values.length) {
                result ~= ",";
            }
            result ~= "\n";
        }

        indentLevel--;
        result ~= "}\n";
        return result.data;
    }

    /**
     * Generate protocol declarations (interfaces in D).
     */
    private string generateProtocolDeclaration(ProtocolDeclaration protocolDecl) {
        auto result = appender!string();
        result ~= "interface " ~ protocolDecl.name ~ " {\n";
        indentLevel++;

        foreach (method; protocolDecl.methods) {
            // Template lifting for 'auto' parameters in protocol method signatures
            string[] templateTypeParams;
            string[string] autoParamToTemplate;
            foreach (i, param; method.parameters) {
                if (param.type == DuendeType.AUTO) {
                    string tname = "T" ~ to!string(i);
                    templateTypeParams ~= tname;
                    autoParamToTemplate[param.name] = tname;
                }
            }

            result ~= indent() ~ toDType(method.returnType) ~ " " ~ method.name;
            if (templateTypeParams.length > 0) {
                result ~= "(" ~ templateTypeParams.join(", ") ~ ")";
            }
            result ~= "(";

            foreach (i, param; method.parameters) {
                if (i > 0) result ~= ", ";
                string pType = (param.type == DuendeType.AUTO)
                    ? autoParamToTemplate[param.name]
                    : toDType(param.type, param.customTypeName);
                result ~= pType ~ " " ~ param.name;
                if (param.defaultValue !is null) {
                    result ~= " = " ~ generateExpression(param.defaultValue);
                }
            }

            result ~= ");\n";
        }

        indentLevel--;
        result ~= "}\n";

        // Generate collective default implementations mixin
        result ~= generateProtocolDefaultsMixin(protocolDecl);

        return result.data;
    }

    /**
     * Generate default implementation mixins for protocols.
     */
    private string generateProtocolDefaultsMixin(ProtocolDeclaration protocolDecl) {
        auto result = appender!string();

        // Check if there are any default implementations
        bool hasDefaults = false;
        foreach (method; protocolDecl.methods) {
            if (method.hasDefaultImplementation) {
                hasDefaults = true;
                break;
            }
        }

        if (!hasDefaults) {
            return "";
        }

        result ~= "\nmixin template " ~ protocolDecl.name ~ "_DefaultImpls() {\n";
        indentLevel++;

        foreach (method; protocolDecl.methods) {
            if (method.hasDefaultImplementation) {
                // Template lifting for 'auto' parameters
                string[] templateTypeParams;
                string[string] autoParamToTemplate;
                foreach (i, param; method.parameters) {
                    if (param.type == DuendeType.AUTO) {
                        string tname = "T" ~ to!string(i);
                        templateTypeParams ~= tname;
                        autoParamToTemplate[param.name] = tname;
                    }
                }

                result ~= indent() ~ toDType(method.returnType) ~ " " ~ method.name;
                if (templateTypeParams.length > 0) {
                    result ~= "(" ~ templateTypeParams.join(", ") ~ ")";
                }
                result ~= "(";
                foreach (i, param; method.parameters) {
                    if (i > 0) result ~= ", ";
                    string pType = (param.type == DuendeType.AUTO)
                        ? autoParamToTemplate[param.name]
                        : toDType(param.type, param.customTypeName);
                    result ~= pType ~ " " ~ param.name;
                    if (param.defaultValue !is null) {
                        result ~= " = " ~ generateExpression(param.defaultValue);
                    }
                }
                result ~= ") const {\n"; // Make default implementations const for immutable compatibility
                indentLevel++;

                foreach (stmt; method.defaultBody) {
                    result ~= generateStatement(stmt);
                }

                indentLevel--;
                result ~= indent() ~ "}\n\n";
            }
        }

        indentLevel--;
        result ~= "}\n";

        return result.data;
    }

    /**
     * Generate method declarations for structs and frames.
     */
    private string generateMethodDeclaration(MethodDeclaration methodDecl, bool isStructMethod = false) {
        auto result = appender!string();

        // Template lifting for 'auto' parameters in methods
        string[] templateTypeParams;
        string[string] autoParamToTemplate;
        foreach (i, param; methodDecl.parameters) {
            if (param.type == DuendeType.AUTO) {
                string tname = "T" ~ to!string(i);
                templateTypeParams ~= tname;
                autoParamToTemplate[param.name] = tname;
            }
        }

        result ~= indent() ~ toDType(methodDecl.returnType) ~ " " ~ methodDecl.name;
        if (templateTypeParams.length > 0) {
            result ~= "(" ~ templateTypeParams.join(", ") ~ ")";
        }
        result ~= "(";

        foreach (i, param; methodDecl.parameters) {
            if (i > 0) result ~= ", ";
            string pType;
            if (param.type == DuendeType.AUTO) {
                pType = autoParamToTemplate[param.name];
            } else {
                pType = toDType(param.type, param.customTypeName);
            }
            result ~= pType ~ " " ~ param.name;
            if (param.defaultValue !is null) {
                result ~= " = " ~ generateExpression(param.defaultValue);
            }
        }

        result ~= ")";
        if (isStructMethod) {
            result ~= " const"; // Make struct methods const for immutable usage
        }
        result ~= " {\n";
        indentLevel++;

        foreach (stmt; methodDecl.body) {
            result ~= generateStatement(stmt);
        }

        indentLevel--;
        result ~= indent() ~ "}\n";
        return result.data;
    }
}