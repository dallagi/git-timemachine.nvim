# git-timemachine.nvim

Neovim plugin to traverse the git history of a file.

Inspired by the `git-timemachine` package for Emacs.

![git-timemachine.nvim demo](demo.svg)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "dallagi/git-timemachine.nvim"
}
```

## Usage

Open a file in a git repository and run:

```vim
:GitTimeMachine
```

Controls:

| Key | Action |
| --- | --- |
| `<C-k>` | Go to previous revision (older) |
| `<C-j>` | Go to next revision (newer) |
| `<Enter>` | Show commit details |
| `q` | Close and return to original buffer |
