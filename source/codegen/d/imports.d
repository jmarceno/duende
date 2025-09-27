module duende.codegen.d.imports;

import duende.ast;
import std.array;
import std.string;

/**
 * Import analysis and generation for D code.
 * This module handles determining which D standard library imports
 * are needed based on the Duende code being compiled.
 */
mixin template DImportsMixin() {
    /**
     * Analyze the entire program to determine which imports are needed.
     * This must be called before code generation to populate requiredImports.
     */
    private void analyzeImports(Program program) {
        // Always need stdio for print/input functions
        requiredImports["std.stdio"] = true;
        // Often needed for formatting (used in match-generated code)
        requiredImports["std.format"] = true;

        foreach (stmt; program.statements) {
            analyzeStatementImports(stmt);
        }
    }

    /**
     * Analyze a statement to determine what imports it needs.
     */
    private void analyzeStatementImports(Statement stmt) {
        if (auto varDecl = cast(VariableDeclaration)stmt) {
            if (varDecl.initializer) {
                analyzeExpressionImports(varDecl.initializer);
            }
            // Check if we need conversion
            if (varDecl.type == DuendeType.STRING || varDecl.type == DuendeType.INT) {
                requiredImports["std.conv"] = true;
            }
            if (varDecl.type == DuendeType.DATE) {
                requiredImports["std.datetime.systime"] = true;
                requiredImports["std.datetime.timezone"] = true;
                requiredImports["core.time"] = true;
            }
        } else if (auto funcDecl = cast(FunctionDeclaration)stmt) {
            foreach (bodyStmt; funcDecl.body) {
                analyzeStatementImports(bodyStmt);
            }
        } else if (auto exprStmt = cast(ExpressionStatement)stmt) {
            analyzeExpressionImports(exprStmt.expression);
        } else if (auto retStmt = cast(ReturnStatement)stmt) {
            if (retStmt.value) {
                analyzeExpressionImports(retStmt.value);
            }
        } else if (auto ifStmt = cast(IfStatement)stmt) {
            analyzeExpressionImports(ifStmt.condition);
            foreach (thenStmt; ifStmt.thenBranch) {
                analyzeStatementImports(thenStmt);
            }
            foreach (elifClause; ifStmt.elifClauses) {
                analyzeExpressionImports(elifClause.condition);
                foreach (elifStmt; elifClause.body) {
                    analyzeStatementImports(elifStmt);
                }
            }
            foreach (elseStmt; ifStmt.elseBranch) {
                analyzeStatementImports(elseStmt);
            }
        } else if (auto forStmt = cast(ForStatement)stmt) {
            analyzeExpressionImports(forStmt.start);
            analyzeExpressionImports(forStmt.end);
            foreach (bodyStmt; forStmt.body) {
                analyzeStatementImports(bodyStmt);
            }
        } else if (auto forInStmt = cast(ForInStatement)stmt) {
            analyzeExpressionImports(forInStmt.iterable);
            foreach (bodyStmt; forInStmt.body) {
                analyzeStatementImports(bodyStmt);
            }
        } else if (auto whileStmt = cast(WhileStatement)stmt) {
            analyzeExpressionImports(whileStmt.condition);
            foreach (bodyStmt; whileStmt.body) {
                analyzeStatementImports(bodyStmt);
            }
        } else if (auto protocolDecl = cast(ProtocolDeclaration)stmt) {
            // Protocols generate format calls in default implementations
            requiredImports["std.format"] = true;
        } else if (auto structDecl = cast(StructDeclaration)stmt) {
            foreach (method; structDecl.methods) {
                analyzeStatementImports(method);
            }
        } else if (auto frameDecl = cast(FrameDeclaration)stmt) {
            foreach (field; frameDecl.fields) {
                analyzeStatementImports(field);
            }
            foreach (method; frameDecl.methods) {
                analyzeStatementImports(method);
            }
        } else if (auto methodDecl = cast(MethodDeclaration)stmt) {
            foreach (bodyStmt; methodDecl.body) {
                analyzeStatementImports(bodyStmt);
            }
        } else if (auto matchStmt = cast(MatchStatement)stmt) {
            analyzeExpressionImports(matchStmt.subject);
            foreach (c; matchStmt.cases) {
                if (auto ep = cast(ExpressionPattern)c.pattern) {
                    analyzeExpressionImports(ep.expr);
                }
                if (c.guard) analyzeExpressionImports(c.guard);
                foreach (s; c.body) analyzeStatementImports(s);
            }
        }
    }

    /**
     * Analyze an expression to determine what imports it needs.
     */
    private void analyzeExpressionImports(Expression expr) {
        if (auto binary = cast(BinaryExpression)expr) {
            analyzeExpressionImports(binary.left);
            analyzeExpressionImports(binary.right);
        } else if (auto unary = cast(UnaryExpression)expr) {
            analyzeExpressionImports(unary.operand);
        } else if (auto call = cast(CallExpression)expr) {
            foreach (arg; call.arguments) {
                analyzeExpressionImports(arg);
            }
            if (call.name == "safeCast") {
                requiredImports["std.conv"] = true;
                requiredImports["std.math"] = true;
            }
            if (call.name == "len") {
                requiredImports["std.conv"] = true;
            }
            // System built-ins
            if (call.name == "osName" || call.name == "osVersion" || call.name == "cpuArch" || call.name == "args") {
                requiredImports["__duende_system_helpers"] = true;
            }
            if (call.name == "osVersion") {
                // We may spawn a subprocess to fetch kernel version on Posix/Windows fallback
                requiredImports["std.process"] = true;
                requiredImports["std.string"] = true;
                requiredImports["std.file"] = true;
            }
            // Check for input function
            if (call.name == "input") {
                requiredImports["std.string"] = true;
            }
            // Sleep requires core.thread and core.time
            if (call.name == "sleep") {
                requiredImports["core.thread"] = true;
                requiredImports["core.time"] = true;
            }
            // Math built-ins require std.math
            if (call.name == "sin" || call.name == "cos" || call.name == "tan" ||
                call.name == "sinDeg" || call.name == "cosDeg" || call.name == "tanDeg" ||
                call.name == "sqrt" || call.name == "pow" || call.name == "log" || call.name == "exp" ||
                call.name == "floor" || call.name == "ceil" || call.name == "round" ||
                call.name == "abs" || call.name == "toRadians" || call.name == "toDegrees" || call.name == "roundTo") {
                requiredImports["std.math"] = true;
            }
            if (call.name == "formatFloat") {
                requiredImports["std.format"] = true;
            }
            // Date/time builtins imports
            if (call.name == "now" || call.name == "utcNow" || call.name == "date" || call.name == "dateTime" || call.name == "parseDate" || call.name == "toUTC" || call.name == "toLocal" || call.name == "toTZ" || call.name == "daysBetween" || call.name == "addDays" || call.name == "addHours" || call.name == "addMinutes" || call.name == "addSeconds" || call.name == "formatDate") {
                requiredImports["std.datetime.systime"] = true;
                if (call.name == "toTZ" || call.name == "utcNow") requiredImports["std.datetime.timezone"] = true;
                if (call.name == "toTZ" || call.name == "daysBetween" || call.name == "addDays" || call.name == "addHours" || call.name == "addMinutes" || call.name == "addSeconds") requiredImports["core.time"] = true;
                if (call.name == "date" || call.name == "dateTime") requiredImports["std.datetime.date"] = true;
            }
            // File I/O builtins imports
            if (call.name == "readText" || call.name == "readBytes" || call.name == "writeText" || call.name == "writeBytes" || call.name == "appendText" || call.name == "appendBytes" || call.name == "readLines" || call.name == "writeLines" || call.name == "appendLines" || call.name == "fileExists" || call.name == "dirExists" || call.name == "deleteFile" || call.name == "listDir" || call.name == "makeDir" || call.name == "removeDir" || call.name == "getCwd" || call.name == "fileSize" || call.name == "getMetadata") {
                requiredImports["std.file"] = true;
            }
            if (call.name == "readLines" || call.name == "writeLines" || call.name == "appendLines") {
                requiredImports["std.array"] = true; requiredImports["std.string"] = true;
            }
            if (call.name == "listDir") {
                requiredImports["std.array"] = true;
            }
            if (call.name == "joinPath") {
                requiredImports["std.path"] = true;
            }
            if (call.name == "getMetadata") {
                requiredImports["std.conv"] = true; requiredImports["std.datetime.systime"] = true;
            }
        } else if (auto assignment = cast(AssignmentExpression)expr) {
            analyzeExpressionImports(assignment.value);
        } else if (auto propAssignment = cast(PropertyAssignmentExpression)expr) {
            analyzeExpressionImports(propAssignment.object);
            analyzeExpressionImports(propAssignment.value);
        } else if (auto interpolation = cast(StringInterpolationExpression)expr) {
            requiredImports["std.format"] = true;
            foreach (subExpr; interpolation.expressions) {
                analyzeExpressionImports(subExpr);
            }
        } else if (auto index = cast(IndexExpression)expr) {
            analyzeExpressionImports(index.object);
            analyzeExpressionImports(index.index);
            requiredImports["std.conv"] = true;
        } else if (auto property = cast(PropertyExpression)expr) {
            analyzeExpressionImports(property.object);
            requiredImports["std.conv"] = true;
        } else if (auto list = cast(ListLiteralExpression)expr) {
            foreach (element; list.elements) {
                analyzeExpressionImports(element);
            }
            requiredImports["std.conv"] = true;
        } else if (auto dict = cast(DictLiteralExpression)expr) {
            foreach (i, key; dict.keys) {
                analyzeExpressionImports(key);
                analyzeExpressionImports(dict.values[i]);
            }
            requiredImports["std.array"] = true;
            requiredImports["std.conv"] = true;
        } else if (auto method = cast(MethodCallExpression)expr) {
            analyzeExpressionImports(method.object);
            foreach (arg; method.arguments) {
                analyzeExpressionImports(arg);
            }
            requiredImports["std.conv"] = true;
            // Check for specific method requirements
            if (method.method == "slice") {
                requiredImports["std.string"] = true;
                // Slicing bytes uses array slicing; no extra imports
            } else if (method.method == "matchAll") {
                requiredImports["std.regex"] = true;
                requiredImports["std.array"] = true;
            } else if (method.method == "match" || method.method == "matchFirst" || method.method == "replaceAll") {
                requiredImports["std.regex"] = true;
            } else if (method.method == "split" || method.method == "toUpperCase" || method.method == "toLowerCase" || method.method == "trim" || method.method == "substring" || method.method == "indexOf" || method.method == "lastIndexOf" || method.method == "startsWith" || method.method == "endsWith" || method.method == "format" || method.method == "formatNumber" || method.method == "charAt" || method.method == "charCodeAt") {
                requiredImports["std.string"] = true;
                if (method.method == "split") requiredImports["std.array"] = true;
            } else if (method.method == "upper" || method.method == "lower") {
                requiredImports["std.string"] = true;
            } else if (method.method == "find") {
                requiredImports["std.algorithm.searching"] = true;
            } else if (method.method == "contains") {
                requiredImports["std.algorithm.searching"] = true;
            } else if (method.method == "sort") {
                requiredImports["std.algorithm.sorting"] = true;
            } else if (method.method == "join") {
                requiredImports["std.array"] = true;
            } else if (method.method == "replace") {
                requiredImports["std.string"] = true;
                // regex variant handled above
            } else if (method.method == "forEach" || method.method == "map" || method.method == "filter") {
                requiredImports["std.array"] = true;
            }
        } else if (auto regex = cast(RegexLiteralExpression)expr) {
            requiredImports["std.regex"] = true;
        } else if (auto constructor = cast(ConstructorCallExpression)expr) {
            foreach (arg; constructor.arguments) {
                analyzeExpressionImports(arg);
            }
        } else if (auto lambda = cast(LambdaExpression)expr) {
            analyzeExpressionImports(lambda.body);
        } else if (auto matchExpr = cast(MatchExpression)expr) {
            analyzeExpressionImports(matchExpr.subject);
            foreach (c; matchExpr.cases) {
                if (auto ep = cast(ExpressionPattern)c.pattern) {
                    analyzeExpressionImports(ep.expr);
                }
                if (c.guard) analyzeExpressionImports(c.guard);
                analyzeExpressionImports(c.value);
            }
        } else if (auto castExpr = cast(CastExpression)expr) {
            analyzeExpressionImports(castExpr.value);
            requiredImports["std.conv"] = true;
            // int(float("NaN")) handling uses isNaN
            requiredImports["std.math"] = true;
        }
    }

    /**
     * Generate the import statements based on analysis.
     * Only includes imports that are actually needed.
     */
    private void generateImports(ref Appender!string result) {
        string[] imports = [
            "std.stdio",
            "std.conv",
            "std.string",
            "std.array",
            "std.format",
            "std.variant",
            "std.regex",
            "std.math",
            "std.algorithm.searching",
            "std.algorithm.sorting",
            "std.datetime.date",
            "std.datetime.systime",
            "std.datetime.timezone",
            "std.file",
            "std.path",
            "core.thread",
            "core.time"
        ];

        foreach (importName; imports) {
            if (importName in requiredImports) {
                result ~= "import " ~ importName ~ ";\n";
            }
        }
        result ~= "\n";
    }
}