# dotfiles

Clone this repository in `~/dotfiles` and use Stow for the configuration files.

## tmux picker

The picker is maintained in [Prometheus1400/tmux-picker](https://github.com/Prometheus1400/tmux-picker)
and installed by TPM. After reloading tmux configuration, press Prefix-I to
install plugins. Press Prefix-U to update them. Prefix-o opens the picker.

Install tmux 3.3+, fzf 0.71+, and Lua 5.1+ or LuaJIT separately. Their executables
must be available in tmux's PATH. When changing your shell PATH on an existing
server, run `tmux set-environment -g PATH "$PATH"` and
`tmux set-environment PATH "$PATH"` from that shell.

Picker development lives in a separate checkout at `~/Repos/tmux-picker`:

```sh
git clone git@github.com:Prometheus1400/tmux-picker.git ~/Repos/tmux-picker
cd ~/Repos/tmux-picker
tests/run
TPM_SOURCE="$HOME/.tmux/plugins/tpm" python3 tests/tpm.py
```

The TPM clone is the runtime copy. Make picker changes in the development
checkout, publish them, then update the installed plugin through TPM.
