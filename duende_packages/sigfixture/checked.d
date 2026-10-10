module duende_packages.sigfixture.checked;

import duende_runtime;

long scale(long n, long factor = 2) {
    return n * factor;
}

Result!(long[]) box(Result!(long[]) value) {
    return value;
}

string echo(string text) {
    return text;
}
