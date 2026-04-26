#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PREFIX="/data/data/com.termux/files/usr"
HOME_DIR="/data/data/com.termux/files/home"

mkdir -p "$HOME_DIR/bin" "$HOME_DIR/projects" "$HOME_DIR/tmp" "$HOME_DIR/.android"

cat >"$HOME_DIR/.profile" <<'EOF'
if [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi
EOF

cat >"$HOME_DIR/.bashrc" <<'EOF'
export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export PATH="$HOME/bin:$PREFIX/bin:$PATH"
export LANG=C.UTF-8
export TERM=xterm-256color
export EDITOR=vim
export VISUAL=vim
export PAGER=less
export LESS='-R'
export JAVA_HOME=/data/data/com.termux/files/usr/lib/jvm/java-21-openjdk
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/android-sdk}"
export ANDROID_HOME="$ANDROID_SDK_ROOT"

alias ll='ls -lh'
alias la='ls -lah'
alias lt='tree -L 2'
alias gs='git status -sb'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias py='python'
alias ports='ss -tulpn'
alias cls='clear'
alias ..='cd ..'
alias ...='cd ../..'

mkcd() {
  mkdir -p "$1" && cd "$1"
}

croot() {
  cd "$HOME/projects"
}

devcheck() {
  echo "python: $(python --version 2>/dev/null)"
  echo "node: $(node --version 2>/dev/null)"
  echo "npm: $(npm --version 2>/dev/null)"
  echo "java: $(java -version 2>&1 | head -n 1)"
  echo "git: $(git --version 2>/dev/null)"
  echo "gradle: $(gradle --version 2>/dev/null | head -n 1)"
  echo "aapt: $(aapt v 2>/dev/null | head -n 1)"
  echo "apksigner: $(apksigner --version 2>/dev/null)"
}

if [ -t 1 ]; then
  PS1='\[\e[38;5;45m\]\u@\h\[\e[0m\] \[\e[38;5;214m\]\W\[\e[0m\] \$ '
fi
EOF

cat >"$HOME_DIR/bin/devcheck" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export PATH="$HOME/bin:$PREFIX/bin:$PATH"
export JAVA_HOME=/data/data/com.termux/files/usr/lib/jvm/java-21-openjdk
export PATH="$JAVA_HOME/bin:$PATH"
python --version
node --version
npm --version
java -version 2>&1 | head -n 2
git --version
gradle --version | head -n 3
aapt v | head -n 1
apksigner --version
EOF

chmod 700 "$HOME_DIR/bin/devcheck"
chmod 600 "$HOME_DIR/.bashrc" "$HOME_DIR/.profile"

printf 'Termux bootstrap complete.\n'
printf 'Use: source ~/.bashrc && devcheck\n'
