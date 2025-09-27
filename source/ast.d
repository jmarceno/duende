module duende.ast;

import std.variant;
import std.conv;

// Position information for error reporting
struct SourcePosition {
    int line;
    int column;
    string file;
    
    this(int line, int column, string file = "") {
        this.line = line;
        this.column = column;
        this.file = file;
    }
    
    string toString() const {
        if (file.length > 0) {
            return file ~ ":" ~ line.to!string ~ ":" ~ column.to!string;
        }
        return line.to!string ~ ":" ~ column.to!string;
    }
}

interface ASTNode {
}

interface Statement : ASTNode {
}

interface Expression : ASTNode {
}

// Patterns for match statements/expressions
interface Pattern : ASTNode {
}

// Mixin template for position tracking
mixin template PositionMixin() {
    private SourcePosition _position;
    
    @property SourcePosition position() const { return _position; }
    @property void position(SourcePosition pos) { _position = pos; }
}

class WildcardPattern : Pattern {
    mixin PositionMixin;
    this() {}
}

class ExpressionPattern : Pattern {
    mixin PositionMixin;
    Expression expr;
    this(Expression expr) { this.expr = expr; }
}

class ResultOkPattern : Pattern {
    mixin PositionMixin;
    string bindName; // variable to bind inside arm (optional, empty means no binding)
    this(string bindName) { this.bindName = bindName; }
}

class ResultErrorPattern : Pattern {
    mixin PositionMixin;
    string bindName; // variable to bind inside arm (optional)
    this(string bindName) { this.bindName = bindName; }
}

class Program : ASTNode {
    mixin PositionMixin;
    Statement[] statements;

    this(Statement[] statements) {
        this.statements = statements;
    }
}

// Import declarations for modules
struct ImportItemSpec {
    string name;    // symbol name in the source module
    string localAlias;   // local alias (optional)
}

class ImportDeclaration : Statement {
    mixin PositionMixin;
    string[] modulePath;      // dotted path segments, e.g., ["modules", "testModule"]
    string moduleAlias;       // optional alias for the module as a whole
    bool isPublic;            // re-export
    bool isWildcard;          // import *
    ImportItemSpec[] items;   // selective imports

    this(string[] modulePath, string moduleAlias = null, bool isPublic = false, bool isWildcard = false, ImportItemSpec[] items = null) {
        this.modulePath = modulePath;
        this.moduleAlias = moduleAlias;
        this.isPublic = isPublic;
        this.isWildcard = isWildcard;
        this.items = items;
    }
}

enum DuendeType {
    INT,
    FLOAT,
    STRING,
    BOOL,
    BYTES,
    VOID,
    LIST,
    DICT,
    REGEX,
    DATE,   // Internal date/time type for codegen
    AUTO,
    STRUCT,
    FRAME,
    ENUM,
    PROTOCOL,
    RESULT,  // Result<T> type
    MAYBE,   // Maybe<T> type
    CUSTOM   // For user-defined types
}

class VariableDeclaration : Statement {
    mixin PositionMixin;
    string name;
    DuendeType type;
    string customTypeName; // For custom types
    DuendeType innerType;  // For generic types like Result<T>, Maybe<T>
    string innerCustomTypeName; // For inner custom types like Result<Status>
    Expression initializer;
    bool isMutable;
    bool isGlobal; // Flag to indicate if this is a global variable

    this(string name, DuendeType type, Expression initializer, bool isMutable = false, 
         string customTypeName = null, DuendeType innerType = DuendeType.VOID, string innerCustomTypeName = null, bool isGlobal = false) {
        this.name = name;
        this.type = type;
        this.customTypeName = customTypeName;
        this.innerType = innerType;
        this.innerCustomTypeName = innerCustomTypeName;
        this.initializer = initializer;
        this.isMutable = isMutable;
        this.isGlobal = isGlobal;
    }
}

class FunctionDeclaration : Statement {
    mixin PositionMixin;
    string name;
    DuendeType returnType;
    DuendeType returnInnerType; // For generic return types like Result<T>
    string returnCustomTypeName; // For custom inner types like Result<Status>
    Parameter[] parameters;
    Statement[] body;

    this(string name, DuendeType returnType, Parameter[] parameters, Statement[] body, 
         DuendeType returnInnerType = DuendeType.VOID, string returnCustomTypeName = null) {
        this.name = name;
        this.returnType = returnType;
        this.returnInnerType = returnInnerType;
        this.returnCustomTypeName = returnCustomTypeName;
        this.parameters = parameters;
        this.body = body;
    }
}

struct Parameter {
    string name;
    DuendeType type;
    string customTypeName; // For custom types
    DuendeType innerType;  // For generic types like Result<T>, Maybe<T>
    bool isNamed;
    // Optional default value for parameters (null if no default)
    Expression defaultValue;
}

class ExpressionStatement : Statement {
    mixin PositionMixin;
    Expression expression;

    this(Expression expression) {
        this.expression = expression;
    }
}

// Match (statement form)
class MatchStmtCase : ASTNode {
    mixin PositionMixin;
    Pattern pattern;
    Expression guard; // optional
    Statement[] body; // single-line or multiple statements (we'll use single-line for now)

    this(Pattern pattern, Expression guard, Statement[] body) {
        this.pattern = pattern;
        this.guard = guard;
        this.body = body;
    }
}

class MatchStatement : Statement {
    mixin PositionMixin;
    Expression subject;
    MatchStmtCase[] cases;

    this(Expression subject, MatchStmtCase[] cases) {
        this.subject = subject;
        this.cases = cases;
    }
}

// Match (expression form)
class MatchExprCase : ASTNode {
    mixin PositionMixin;
    Pattern pattern;
    Expression guard; // optional
    Expression value;

    this(Pattern pattern, Expression guard, Expression value) {
        this.pattern = pattern;
        this.guard = guard;
        this.value = value;
    }
}

class MatchExpression : Expression {
    mixin PositionMixin;
    Expression subject;
    MatchExprCase[] cases;

    this(Expression subject, MatchExprCase[] cases) {
        this.subject = subject;
        this.cases = cases;
    }
}

class ReturnStatement : Statement {
    mixin PositionMixin;
    Expression value;

    this(Expression value) {
        this.value = value;
    }
}

class BreakStatement : Statement {
    mixin PositionMixin;
    this() {}
}

class ContinueStatement : Statement {
    mixin PositionMixin;
    this() {}
}

// Represents an elif clause in an if statement
struct ElifClause {
    Expression condition;
    Statement[] body;
}

class IfStatement : Statement {
    mixin PositionMixin;
    Expression condition;
    Statement[] thenBranch;
    ElifClause[] elifClauses;
    Statement[] elseBranch;

    this(Expression condition, Statement[] thenBranch, ElifClause[] elifClauses = null, Statement[] elseBranch = null) {
        this.condition = condition;
        this.thenBranch = thenBranch;
        this.elifClauses = elifClauses;
        this.elseBranch = elseBranch;
    }
}

class ForStatement : Statement {
    mixin PositionMixin;
    string variable;
    Expression start;
    Expression end;
    Statement[] body;

    this(string variable, Expression start, Expression end, Statement[] body) {
        this.variable = variable;
        this.start = start;
        this.end = end;
        this.body = body;
    }
}

class ForInStatement : Statement {
    mixin PositionMixin;
    string variable;
    Expression iterable;
    Statement[] body;

    this(string variable, Expression iterable, Statement[] body) {
        this.variable = variable;
        this.iterable = iterable;
        this.body = body;
    }
}

class WhileStatement : Statement {
    mixin PositionMixin;
    Expression condition;
    Statement[] body;

    this(Expression condition, Statement[] body) {
        this.condition = condition;
        this.body = body;
    }
}

class AssignmentExpression : Expression {
    mixin PositionMixin;
    string variable;
    Expression value;

    this(string variable, Expression value) {
        this.variable = variable;
        this.value = value;
    }
}

class PropertyAssignmentExpression : Expression {
    mixin PositionMixin;
    Expression object;
    string property;
    Expression value;

    this(Expression object, string property, Expression value) {
        this.object = object;
        this.property = property;
        this.value = value;
    }
}

class BinaryExpression : Expression {
    mixin PositionMixin;
    Expression left;
    string operator;
    Expression right;

    this(Expression left, string operator, Expression right) {
        this.left = left;
        this.operator = operator;
        this.right = right;
    }
}

class UnaryExpression : Expression {
    mixin PositionMixin;
    string operator;
    Expression operand;

    this(string operator, Expression operand) {
        this.operator = operator;
        this.operand = operand;
    }
}

class LiteralExpression : Expression {
    mixin PositionMixin;
    Variant value;
    DuendeType type;

    this(int value) {
        this.value = Variant(value);
        this.type = DuendeType.INT;
    }

    this(double value) {
        this.value = Variant(value);
        this.type = DuendeType.FLOAT;
    }

    this(string value) {
        this.value = Variant(value);
        this.type = DuendeType.STRING;
    }

    this(bool value) {
        this.value = Variant(value);
        this.type = DuendeType.BOOL;
    }
}

class VariableExpression : Expression {
    mixin PositionMixin;
    string name;

    this(string name) {
        this.name = name;
    }
}

class CallExpression : Expression {
    mixin PositionMixin;
    string name;
    Expression[] arguments;
    // Optional names for arguments; empty string for positional
    string[] argumentNames;

    this(string name, Expression[] arguments, string[] argumentNames = null) {
        this.name = name;
        this.arguments = arguments;
        this.argumentNames = argumentNames.length ? argumentNames : new string[arguments.length];
    }
}

class StringInterpolationExpression : Expression {
    mixin PositionMixin;
    string[] parts;
    Expression[] expressions;
    // Optional per-expression format specifiers (e.g., %0.2f). Same length as expressions, entries may be null/empty.
    string[] formats;

    this(string[] parts, Expression[] expressions, string[] formats = null) {
        this.parts = parts;
        this.expressions = expressions;
        this.formats = formats.length ? formats : new string[expressions.length];
    }
}

class IndexExpression : Expression {
    mixin PositionMixin;
    Expression object;
    Expression index;

    this(Expression object, Expression index) {
        this.object = object;
        this.index = index;
    }
}

class PropertyExpression : Expression {
    mixin PositionMixin;
    Expression object;
    string property;

    this(Expression object, string property) {
        this.object = object;
        this.property = property;
    }
}

class BytesLiteralExpression : Expression {
    mixin PositionMixin;
    int[] values;

    this(int[] values) {
        this.values = values;
    }
}

class ListLiteralExpression : Expression {
    mixin PositionMixin;
    Expression[] elements;

    this(Expression[] elements) {
        this.elements = elements;
    }
}

class DictLiteralExpression : Expression {
    mixin PositionMixin;
    Expression[] keys;
    Expression[] values;

    this(Expression[] keys, Expression[] values) {
        this.keys = keys;
        this.values = values;
    }
}

class MethodCallExpression : Expression {
    mixin PositionMixin;
    Expression object;
    string method;
    Expression[] arguments;
    // Optional names for arguments; empty string for positional
    string[] argumentNames;

    this(Expression object, string method, Expression[] arguments, string[] argumentNames = null) {
        this.object = object;
        this.method = method;
        this.arguments = arguments;
        this.argumentNames = argumentNames.length ? argumentNames : new string[arguments.length];
    }
}

class RegexLiteralExpression : Expression {
    mixin PositionMixin;
    string pattern;

    this(string pattern) {
        this.pattern = pattern;
    }
}

// New AST nodes for structs, frames, and enums
class StructDeclaration : Statement {
    string name;
    Parameter[] fields;
    MethodDeclaration[] methods;
    Annotation[] annotations;

    this(string name, Parameter[] fields, MethodDeclaration[] methods, Annotation[] annotations = null) {
        this.name = name;
        this.fields = fields;
        this.methods = methods;
        this.annotations = annotations;
    }
}

class FrameDeclaration : Statement {
    string name;
    VariableDeclaration[] fields;
    MethodDeclaration[] methods;
    Annotation[] annotations;

    this(string name, VariableDeclaration[] fields, MethodDeclaration[] methods, Annotation[] annotations = null) {
        this.name = name;
        this.fields = fields;
        this.methods = methods;
        this.annotations = annotations;
    }
}

class EnumDeclaration : Statement {
    string name;
    string[] values;

    this(string name, string[] values) {
        this.name = name;
        this.values = values;
    }
}

class MethodDeclaration : Statement {
    string name;
    DuendeType returnType;
    Parameter[] parameters;
    Statement[] body;

    this(string name, DuendeType returnType, Parameter[] parameters, Statement[] body) {
        this.name = name;
        this.returnType = returnType;
        this.parameters = parameters;
        this.body = body;
    }
}

class ConstructorCallExpression : Expression {
    mixin PositionMixin;
    string typeName;
    Expression[] arguments;
    // Optional names for arguments; empty string for positional
    string[] argumentNames;

    this(string typeName, Expression[] arguments, string[] argumentNames = null) {
        this.typeName = typeName;
        this.arguments = arguments;
        this.argumentNames = argumentNames.length ? argumentNames : new string[arguments.length];
    }
}

// Protocol definitions
class ProtocolDeclaration : Statement {
    string name;
    MethodSignature[] methods;

    this(string name, MethodSignature[] methods) {
        this.name = name;
        this.methods = methods;
    }
}

struct MethodSignature {
    string name;
    DuendeType returnType;
    Parameter[] parameters;
    Statement[] defaultBody; // For default implementations
    bool hasDefaultImplementation;
}

// Annotation support
struct Annotation {
    string name;
    string[] arguments;
}

// Add support for custom type names
struct CustomType {
    DuendeType baseType;
    string typeName;
}

class LambdaExpression : Expression {
    mixin PositionMixin;
    string[] parameters;
    Expression body;

    this(string[] parameters, Expression body) {
        this.parameters = parameters;
        this.body = body;
    }
}

class DeferStatement : Statement {
    Expression call;

    this(Expression call) {
        this.call = call;
    }
}

// Error handling expressions
class ResultConstructorExpression : Expression {
    mixin PositionMixin;
    bool isOk;  // true for Ok, false for Error
    Expression value;

    this(bool isOk, Expression value) {
        this.isOk = isOk;
        this.value = value;
    }
}

class MaybeConstructorExpression : Expression {
    mixin PositionMixin;
    bool isSome;  // true for Some, false for None
    Expression value;  // null for None

    this(bool isSome, Expression value = null) {
        this.isSome = isSome;
        this.value = value;
    }
}

class UnwrapExpression : Expression {
    mixin PositionMixin;
    Expression result;
    Expression defaultValue;

    this(Expression result, Expression defaultValue) {
        this.result = result;
        this.defaultValue = defaultValue;
    }
}

class TryBlockExpression : Expression {
    Statement[] statements;

    this(Statement[] statements) {
        this.statements = statements;
    }
}

class PanicExpression : Expression {
    Expression message;

    this(Expression message) {
        this.message = message;
    }
}

// Type cast expression: int(expr), float(expr), string(expr)
class CastExpression : Expression {
    DuendeType targetType;
    Expression value;

    this(DuendeType targetType, Expression value) {
        this.targetType = targetType;
        this.value = value;
    }
}

// Type literal expression: allows passing a type as a value (e.g., safeCast(int, x))
class TypeLiteralExpression : Expression {
    DuendeType type;
    string customTypeName; // optional for future custom types

    this(DuendeType type, string customTypeName = null) {
        this.type = type;
        this.customTypeName = customTypeName;
    }
}