# ya-tree.nvim - Yet Another Neovim Tree

Ya-Tree is file tree plugin for Neovim. It also supports other tree-like structures.

## Features

- Git integration, including [yadm](https://yadm.io/)
- Search
- Go to node with path completion
- Basic file operations

## Requirements

[neovim >=0.7.0](https://github.com/neovim/neovim/wiki/Installing-Neovim)

### Installation with Packer:
```lua
use({
  "jgottzen/ya-tree.nvim",
  config = function()
    require("ya-tree").setup()
  end,
  requires = {
    "nvim-lua/plenary.nvim",
    "kyazdani42/nvim-web-devicons", -- optional, used for displaying icons
  },
})
```

## Commands

`:YaTreeOpen` or `:YaTreeOpen!` Open the tree window, takes optional arguments.

| Argument     | Description                                                                                                                       |
|--------------|-----------------------------------------------------------------------------------------------------------------------------------|
| **tree**     | The tree to open, default is the current tree, or "filesystem".                                                                   |
| **path**     | The path to open in the tree, defaults to the current working directory, can be `%` to expand to and focus on the current buffer. |
| **focus**    | Wether to enter the tree window.                                                                                                  |
| **position** | Where to position the tree, defaults to the last posisiton or the value set in config.                                            |
| **size**     | The size of the tree window, defaults to the last used size of the value set in config.                                           |

If `!` (bang) is used, the `path` argument will force a tree root change.

Examples:

- `YaTreeOpen size=20 focus tree=git position=top` open the Git tree at the top with a heigh of 20.
- `YaTreeOpen` Open the last used tree or a filesystem tree, in the last used position and size.
- `YaTreeOpen! focus tree=filesystem path=/path/to/directory` Open the filesystem tree and change the root directory to `/path/to/directory` and focus the tree window.
<details>

`:YaTreeClose` Close the tree window.

`:YaTreeToggle` Toggle the tree window.

