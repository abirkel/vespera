# PROVENANCE: ours. Fish-parity (inline autosuggestions, syntax highlighting, menu-driven
#   completion) from Fedora packages only, no oh-my-zsh style framework. Verified with
#   `zsh -n` and an interactive start.
#
# KNOWN, DELIBERATE CLOBBER: this path is owned by the zsh package and marked %config.
# Unlike the qtlogging.ini case, there is no non-clobbering alternative — zsh's startup
# chain (/etc/zshenv, /etc/zprofile, /etc/zshrc, /etc/zlogin) is entirely package-owned
# too and offers no drop-in directory. It is benign: zsh's own /etc/skel/.zshrc is 34
# lines of nothing but commented-out examples, so no content is lost. 99-cleanup.sh
# allows for it explicitly so the rpm -V sweep does not flag it as a surprise.
#
# fish is also installed: `chsh -s /usr/bin/fish`. Either way the shell change lands
# in /etc/passwd — machine state, not the image.

# ---- history: large, shared, deduplicated ----
HISTFILE="${ZDOTDIR:-$HOME}/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt SHARE_HISTORY          # like fish
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt EXTENDED_HISTORY
setopt INC_APPEND_HISTORY

# ---- navigation ----
setopt AUTO_CD                # `foo` instead of `cd foo`
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt INTERACTIVE_COMMENTS
setopt NO_BEEP

# ---- completion: menu-driven, case-insensitive, colourised ----
autoload -Uz compinit
# Rebuild the dump once a day; keeps startup fast.
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
    compinit
else
    compinit -C
fi

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache"

# ---- fish-like autosuggestions ----
if [[ -r /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
    source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    ZSH_AUTOSUGGEST_STRATEGY=(history completion)
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
    # Right arrow accepts the suggestion, as fish does.
    bindkey '^[[C' forward-char
fi

# ---- history substring search: up/down filter by the current line ----
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search

# ---- keybindings ----
bindkey -e                       # emacs mode
bindkey '^[[1;5C' forward-word   # ctrl+right
bindkey '^[[1;5D' backward-word  # ctrl+left
bindkey '^[[3~'   delete-char
bindkey '^[[H'    beginning-of-line
bindkey '^[[F'    end-of-line

# ---- prompt: git-aware, two-line, no framework ----
autoload -Uz vcs_info
precmd_vcs_info() { vcs_info }
precmd_functions+=( precmd_vcs_info )
setopt PROMPT_SUBST
zstyle ':vcs_info:git:*' formats       ' %F{magenta}%b%f'
zstyle ':vcs_info:git:*' actionformats ' %F{magenta}%b%f %F{red}(%a)%f'
PROMPT='%F{blue}%~%f${vcs_info_msg_0_}
%(?.%F{green}.%F{red})❯%f '

# ---- integrations ----
# fzf is in the base image.
[[ -r /usr/share/fzf/shell/key-bindings.zsh ]] && source /usr/share/fzf/shell/key-bindings.zsh
# No fpath edit for ujust completion: /usr/share/zsh/site-functions is already in zsh's
# default fpath, and _comps[ujust] registers from a bare compinit (verified). An earlier
# version appended it here, which was dead twice over — redundant, and after compinit.

# ---- syntax highlighting MUST be sourced last ----
if [[ -r /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
