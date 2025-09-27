# KDE Kate Syntax Highlighting for Duende

This directory contains the Kate syntax highlighting definition for Duende language files (`.du` and `.duende`).

## Installation

The KDE Syntax Highlighting framework (KSyntaxHighlighting) looks for definitions in these locations. Use the one that matches your setup.

### User installation (recommended)
Copy `duende.xml` to your per-user data directory for KSyntaxHighlighting:

```bash
mkdir -p ~/.local/share/org.kde.syntax-highlighting/syntax/
cp duende.xml ~/.local/share/org.kde.syntax-highlighting/syntax/
```

Then restart Kate/KWrite (or any app using KSyntaxHighlighting).

### System-wide installation (requires sudo)
Copy `duende.xml` to the system data directory used by KSyntaxHighlighting:

```bash
sudo install -D -m 0644 duende.xml /usr/share/org.kde.syntax-highlighting/syntax/duende.xml
```

Restart applications to pick up the new definition.