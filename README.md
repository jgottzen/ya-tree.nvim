# ya-tree.nvim - Yet Another Neovim Tree

Ya-Tree is file tree plugin for Neovim. It also supports other tree-like structures.

## Features

- Git integration, including [yadm](https://yadm.io/)
- Search
- Go to node with path completion
- Basic file operations

## Requirements

[neovim >= 0.7.0](https://github.com/neovim/neovim/wiki/Installing-Neovim)

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

`:YaTreeOpen` Open the tree window, takes optional arguments.

| Argument           | Description                                                                                                                       |
|--------------------|-----------------------------------------------------------------------------------------------------------------------------------|
| **tree=\<tree\>**    | The tree to open, default is the current tree, or "filesystem".                                                                   |
| **path=\<path\>**    | The path to open in the tree, defaults to the current working directory, can be `%` to expand to and focus on the current buffer. If the path is outside the current root, the root will change to the path. |
| **focus**          | Enter the tree window.                                                                                                            |
| **position=\<pos\>** | Where to position the tree, defaults to the last posisiton or the value set in config.                                            |
| **size=\<size\>**    | The size of the tree window, defaults to the last used size of the value set in config.                                           |

Examples:

- `YaTreeOpen size=20 focus tree=git position=top` Open the Git tree at the top with a heigh of 20, and focus it.
- `YaTreeOpen` Open the last used tree or a filesystem tree, in the last used position and size, or the configured size.
- `YaTreeOpen tree=filesystem path=/path/to/directory` Open the filesystem tree and change the root directory to `/path/to/directory`.
- `YaTreeOpen path=%` Open the current tree, or filesystem, and expand the tree to the path of the current buffer, if possible. If the path is not located in the current root directory, the root will change the directory containing the path.

`:YaTreeClose` Close the tree window.

`:YaTreeToggle` Toggle the tree window.

