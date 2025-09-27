module duende.lexer;

import std.range;
import std.conv;
import std.string;
import std.ascii : isDigit, isAlpha, isAlphaNum, isWhite;

enum TokenType {
    // Literals
    INTEGER,
    FLOAT,
    STRING,
    BOOLEAN,
    BYTES,

    // Identifiers and keywords
    IDENTIFIER,
    LET,
    VAR,
    IF,
    ELIF,
    ELSE,
    BREAK,
    CONTINUE,
    MATCH,
    DO,
    END,
    FOR,
    IN,
    WHILE,
    RETURN,
    FUNCTION,
    REGEX,
    STRUCT,
    FRAME,
    ENUM,
    PROTOCOL,
    IMPLEMENTS,
    THIS,
    DEFER,
    TRY,
    PANIC,
    IMPORT,
    AS,
    PUBLIC,
    PRIVATE,

    // Error handling constructors
    OK,
    ERROR,
    SOME,
    NONE,
    RESULT,
    MAYBE,

    // Types
    INT_TYPE,
    FLOAT_TYPE,
    STRING_TYPE,
    BOOL_TYPE,
    BYTES_TYPE,
    VOID_TYPE,
    LIST_TYPE,
    DICT_TYPE,
    REGEX_TYPE,
    AUTO_TYPE,

    // Operators
    PLUS,
    MINUS,
    MULTIPLY,
    DIVIDE,
    ASSIGN,
    EQUAL,
    NOT_EQUAL,
    LESS,
    LESS_EQUAL,
    GREATER,
    GREATER_EQUAL,
    LOGICAL_AND,
    LOGICAL_OR,
    LOGICAL_NOT,
    QUESTION_ELSE,  // ? else operator
    MODULO,

    // Punctuation
    LEFT_PAREN,
    RIGHT_PAREN,
    LEFT_BRACKET,
    RIGHT_BRACKET,
    LEFT_BRACE,
    RIGHT_BRACE,
    COMMA,
    DOT,
    COLON,
    RANGE,
    DOLLAR_BRACE,
    AT,
    ARROW,
    QUESTION,

    // Special
    NEWLINE,
    EOF,
    COMMENT
}

struct Token {
    TokenType type;
    string value;
    int line;
    int column;
}

class Lexer {
    private string source;
    private size_t pos;
    private size_t line;
    private size_t column;
    // Sentinel used to mark escaped interpolation tokens in string literals
    // so the parser can distinguish literal "${" and "}" from interpolation control.
    private enum char ESC_INTERP = cast(char)0x1D; // Group Separator

    this(string source) {
        this.source = source;
        this.pos = 0;
        this.line = 1;
        this.column = 1;
    }

    Token[] tokenize() {
        Token[] tokens;

        while (!atEnd()) {
            Token token = nextToken();
            if (token.type != TokenType.COMMENT) {
                tokens ~= token;
            }
        }

        tokens ~= Token(TokenType.EOF, "", cast(int)line, cast(int)column);
        return tokens;
    }

    private Token nextToken() {
        skipWhitespace();

        if (atEnd()) {
            return Token(TokenType.EOF, "", cast(int)line, cast(int)column);
        }

        size_t startLine = line;
        size_t startColumn = column;
        char c = advance();

        switch (c) {
            case 'b':
                // Bytes literal prefix: b"..."
                if (peek() == '"') {
                    return bytesString(startLine, startColumn);
                } else {
                    // fall back to identifier starting with 'b'
                    pos--; column--;
                    return identifier(startLine, startColumn);
                }
            case '\'':
                // Single-quoted string literal support
                return stringSingle(startLine, startColumn);
            case '\n':
                line++;
                column = 1;
                return Token(TokenType.NEWLINE, "\n", cast(int)startLine, cast(int)startColumn);
            case '(':
                return Token(TokenType.LEFT_PAREN, "(", cast(int)startLine, cast(int)startColumn);
            case ')':
                return Token(TokenType.RIGHT_PAREN, ")", cast(int)startLine, cast(int)startColumn);
            case '[':
                return Token(TokenType.LEFT_BRACKET, "[", cast(int)startLine, cast(int)startColumn);
            case ']':
                return Token(TokenType.RIGHT_BRACKET, "]", cast(int)startLine, cast(int)startColumn);
            case ',':
                return Token(TokenType.COMMA, ",", cast(int)startLine, cast(int)startColumn);
            case ':':
                return Token(TokenType.COLON, ":", cast(int)startLine, cast(int)startColumn);
            case '+':
                return Token(TokenType.PLUS, "+", cast(int)startLine, cast(int)startColumn);
            case '-':
                if (peek() == '>') {
                    advance();
                    return Token(TokenType.ARROW, "->", cast(int)startLine, cast(int)startColumn);
                }
                return Token(TokenType.MINUS, "-", cast(int)startLine, cast(int)startColumn);
            case '*':
                return Token(TokenType.MULTIPLY, "*", cast(int)startLine, cast(int)startColumn);
            case '/':
                if (peek() == '/') {
                    return comment();
                }
                if (peek() == '*') {
                    return blockComment();
                }
                return Token(TokenType.DIVIDE, "/", cast(int)startLine, cast(int)startColumn);
            case '%':
                return Token(TokenType.MODULO, "%", cast(int)startLine, cast(int)startColumn);
            case '=':
                if (peek() == '=') {
                    advance();
                    return Token(TokenType.EQUAL, "==", cast(int)startLine, cast(int)startColumn);
                }
                return Token(TokenType.ASSIGN, "=", cast(int)startLine, cast(int)startColumn);
            case '!':
                if (peek() == '=') {
                    advance();
                    return Token(TokenType.NOT_EQUAL, "!=", cast(int)startLine, cast(int)startColumn);
                }
                return Token(TokenType.LOGICAL_NOT, "!", cast(int)startLine, cast(int)startColumn);
            case '<':
                if (peek() == '=') {
                    advance();
                    return Token(TokenType.LESS_EQUAL, "<=", cast(int)startLine, cast(int)startColumn);
                }
                return Token(TokenType.LESS, "<", cast(int)startLine, cast(int)startColumn);
            case '>':
                if (peek() == '=') {
                    advance();
                    return Token(TokenType.GREATER_EQUAL, ">=", cast(int)startLine, cast(int)startColumn);
                }
                return Token(TokenType.GREATER, ">", cast(int)startLine, cast(int)startColumn);
            case '&':
                if (peek() == '&') {
                    advance();
                    return Token(TokenType.LOGICAL_AND, "&&", cast(int)startLine, cast(int)startColumn);
                }
                break;
            case '|':
                if (peek() == '|') {
                    advance();
                    return Token(TokenType.LOGICAL_OR, "||", cast(int)startLine, cast(int)startColumn);
                }
                break;
            case '.':
                if (peek() == '.') {
                    advance();
                    return Token(TokenType.RANGE, "..", cast(int)startLine, cast(int)startColumn);
                }
                return Token(TokenType.DOT, ".", cast(int)startLine, cast(int)startColumn);
            case '"':
                return string_(startLine, startColumn);
            case '{':
                return Token(TokenType.LEFT_BRACE, "{", cast(int)startLine, cast(int)startColumn);
            case '}':
                return Token(TokenType.RIGHT_BRACE, "}", cast(int)startLine, cast(int)startColumn);
            case '@':
                return Token(TokenType.AT, "@", cast(int)startLine, cast(int)startColumn);
            case '?':
                return Token(TokenType.QUESTION, "?", cast(int)startLine, cast(int)startColumn);
            default:
                if (isDigit(c)) {
                    pos--; column--;
                    return number(startLine, startColumn);
                }
                if (isAlpha(c) || c == '_') {
                    pos--; column--;
                    return identifier(startLine, startColumn);
                }
                break;
        }

        throw new Exception("Unexpected character: " ~ c);
    }

    private Token comment() {
        size_t startLine = line;
        size_t startColumn = column - 2;

        string value = "//";
        while (!atEnd() && peek() != '\n') {
            value ~= advance();
        }

        return Token(TokenType.COMMENT, value, cast(int)startLine, cast(int)startColumn);
    }

    private Token blockComment() {
        // We have just consumed '/', and peek() is '*'.
        size_t startLine = line;
        size_t startColumn = column - 1; // the '/' was at column-1, now at '*'

        // Consume the '*'
        advance();

        string value = "/*";

        while (!atEnd()) {
            char ch = advance();
            value ~= ch;

            if (ch == '\n') {
                // Maintain accurate line/column for newlines inside block comments
                line++;
                column = 1;
            }

            // Check for closing '*/'
            if (ch == '*' && !atEnd() && peek() == '/') {
                value ~= advance(); // consume '/'
                break;
            }
        }

        if (atEnd() && (value.length < 2 || value[$-2 .. $] != "*/")) {
            throw new Exception("Unterminated block comment");
        }

        return Token(TokenType.COMMENT, value, cast(int)startLine, cast(int)startColumn);
    }

    private Token string_(size_t startLine, size_t startColumn) {
        string value = "";

        while (!atEnd() && peek() != '"') {
            if (peek() == '\\') {
                advance();
                if (!atEnd()) {
                    char escaped = advance();
                    switch (escaped) {
                        case 'n': value ~= '\n'; break;
                        case 't': value ~= '\t'; break;
                        case 'r': value ~= '\r'; break;
                        case '\\': value ~= '\\'; break;
                        case '"': value ~= '"'; break;
                        // Escape interpolation tokens so parser doesn't treat them as control
                        case '$':
                            if (!atEnd() && peek() == '{') {
                                // escaped sequence \${ -> emit literal '$' then sentinel+'{' to avoid interpolation start
                                value ~= '$';
                                value ~= ESC_INTERP;
                                value ~= '{';
                                advance(); // consume '{'
                            } else {
                                value ~= '$';
                            }
                            break;
                        case '}':
                            // escaped closing brace -> sentinel marks literal '}' so parser won't close
                            value ~= ESC_INTERP;
                            value ~= '}';
                            break;
                        default:
                            value ~= escaped;
                            break;
                    }
                }
            } else {
                value ~= advance();
            }
        }

        if (atEnd()) {
            throw new Exception("Unterminated string");
        }

        advance(); // closing quote
        return Token(TokenType.STRING, value, cast(int)startLine, cast(int)startColumn);
    }

    private Token stringSingle(size_t startLine, size_t startColumn) {
        // Single-quoted strings behave same as double regarding escapes,
        // but we still carry interpolation sentinels so parser treats \${ and \} as literals.
        string value = "";
        while (!atEnd() && peek() != '\'') {
            if (peek() == '\\') {
                advance();
                if (!atEnd()) {
                    char escaped = advance();
                    switch (escaped) {
                        case 'n': value ~= '\n'; break;
                        case 't': value ~= '\t'; break;
                        case 'r': value ~= '\r'; break;
                        case '\\': value ~= '\\'; break;
                        case '\'': value ~= '\''; break;
                        case '$':
                            if (!atEnd() && peek() == '{') { value ~= '$'; value ~= ESC_INTERP; value ~= '{'; advance(); }
                            else { value ~= '$'; }
                            break;
                        case '}':
                            value ~= ESC_INTERP; value ~= '}';
                            break;
                        default: value ~= escaped; break;
                    }
                }
            } else {
                value ~= advance();
            }
        }
        if (atEnd()) throw new Exception("Unterminated string");
        advance();
        return Token(TokenType.STRING, value, cast(int)startLine, cast(int)startColumn);
    }

    private Token bytesString(size_t startLine, size_t startColumn) {
        // We have just consumed the 'b', and peek() is '"'
        advance(); // consume opening quote

        string value = "";

        while (!atEnd() && peek() != '"') {
            if (peek() == '\\') {
                advance();
                if (!atEnd()) {
                    char escaped = advance();
                    switch (escaped) {
                        case 'n': value ~= '\n'; break;
                        case 't': value ~= '\t'; break;
                        case 'r': value ~= '\r'; break;
                        case '\\': value ~= '\\'; break;
                        case '"': value ~= '"'; break;
                        // For bytes, treat interpolation escapes literally too
                        case '$':
                            if (!atEnd() && peek() == '{') { value ~= '$'; value ~= '{'; advance(); }
                            else { value ~= '$'; }
                            break;
                        case '}': value ~= '}'; break;
                        default: value ~= escaped; break;
                    }
                }
            } else {
                value ~= advance();
            }
        }

        if (atEnd()) {
            throw new Exception("Unterminated bytes literal");
        }

        advance(); // closing quote
        return Token(TokenType.BYTES, value, cast(int)startLine, cast(int)startColumn);
    }

    private Token number(size_t startLine, size_t startColumn) {
        string value = "";
        bool isFloat = false;

        while (!atEnd() && isDigit(peek())) {
            value ~= advance();
        }

        if (!atEnd() && peek() == '.' && isDigit(peekNext())) {
            isFloat = true;
            value ~= advance(); // dot
            while (!atEnd() && isDigit(peek())) {
                value ~= advance();
            }
        }

        TokenType type = isFloat ? TokenType.FLOAT : TokenType.INTEGER;
        return Token(type, value, cast(int)startLine, cast(int)startColumn);
    }

    private Token identifier(size_t startLine, size_t startColumn) {
        string value = "";

        while (!atEnd() && (isAlphaNum(peek()) || peek() == '_')) {
            value ~= advance();
        }

        TokenType type = getKeywordType(value);
        return Token(type, value, cast(int)startLine, cast(int)startColumn);
    }

    private TokenType getKeywordType(string value) {
        switch (value) {
            case "let": return TokenType.LET;
            case "var": return TokenType.VAR;
            case "if": return TokenType.IF;
            case "elif": return TokenType.ELIF;
            case "else": return TokenType.ELSE;
            case "break": return TokenType.BREAK;
            case "continue": return TokenType.CONTINUE;
            case "match": return TokenType.MATCH;
            case "do": return TokenType.DO;
            case "end": return TokenType.END;
            case "for": return TokenType.FOR;
            case "in": return TokenType.IN;
            case "while": return TokenType.WHILE;
            case "return": return TokenType.RETURN;
            case "try": return TokenType.TRY;
            case "panic": return TokenType.PANIC;
            case "import": return TokenType.IMPORT;
            case "as": return TokenType.AS;
            case "public": return TokenType.PUBLIC;
            case "private": return TokenType.PRIVATE;
            case "Ok": return TokenType.OK;
            case "Error": return TokenType.ERROR;
            case "Some": return TokenType.SOME;
            case "None": return TokenType.NONE;
            case "Result": return TokenType.RESULT;
            case "Maybe": return TokenType.MAYBE;
            case "int": return TokenType.INT_TYPE;
            case "float": return TokenType.FLOAT_TYPE;
            case "string": return TokenType.STRING_TYPE;
            case "bool": return TokenType.BOOL_TYPE;
            case "bytes": return TokenType.BYTES_TYPE;
            case "void": return TokenType.VOID_TYPE;
            case "list": return TokenType.LIST_TYPE;
            case "dict": return TokenType.DICT_TYPE;
            case "auto": return TokenType.AUTO_TYPE;
            case "struct": return TokenType.STRUCT;
            case "frame": return TokenType.FRAME;
            case "enum": return TokenType.ENUM;
            case "protocol": return TokenType.PROTOCOL;
            case "this": return TokenType.THIS;
            case "defer": return TokenType.DEFER;
            case "true", "false": return TokenType.BOOLEAN;
            default: return TokenType.IDENTIFIER;
        }
    }

    private void skipWhitespace() {
        while (!atEnd() && isWhite(peek()) && peek() != '\n') {
            advance();
        }
    }

    private char advance() {
        if (atEnd()) return '\0';
        column++;
        return source[pos++];
    }

    private char peek() {
        if (atEnd()) return '\0';
        return source[pos];
    }

    private char peekNext() {
        if (pos + 1 >= source.length) return '\0';
        return source[pos + 1];
    }

    private bool atEnd() {
        return pos >= source.length;
    }
}