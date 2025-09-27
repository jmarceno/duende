# Duende Nano Syntax Highlighting

This directory contains syntax highlighting configuration for the Duende programming language in the Nano text editor.

## Installation

### Option 1: System-wide installation (requires sudo)

Copy the syntax file to the nano syntax directory:

```bash
sudo cp duende.nanorc /usr/share/nano/
```

Then add the following line to `/etc/nanorc` or create it if it doesn't exist:

```bash
echo "include /usr/share/nano/duende.nanorc" | sudo tee -a /etc/nanorc
```

### Option 2: User-specific installation

Copy the syntax file to your home directory:

```bash
mkdir -p ~/.nano
cp duende.nanorc ~/.nano/
```

Then add the following line to your `~/.nanorc` file (create it if it doesn't exist):

```bash
echo "include ~/.nano/duende.nanorc" >> ~/.nanorc
```

### Option 3: Direct inclusion

You can also directly include the absolute path in your `~/.nanorc`:

```bash
echo "include $(pwd)/duende.nanorc" >> ~/.nanorc
```
