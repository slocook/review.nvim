# review.nvim

Capture code review comments from diffs and export them for AI iteration or Beads.

## Requirements

- Neovim 0.12+
- Lua-only configuration
- Optional: `bd` CLI for Beads integration

## Install (Lazy.nvim)

```lua
{
  "yourname/review.nvim",
  dependencies = {
    "esmuellert/codediff.nvim",
  },
  config = function()
    require("review").setup({
      export = {
        mode = "single", -- "single" | "per_comment"
      },
      beads = {
        enabled = false,
        branch_pattern = "epic/([^/]+)",
      },
    })
  end,
}
```

## Commands

- `:ReviewComment` (use visual line/block selection or current line)
- `:ReviewList` (list/edit/delete/jump)
- `:ReviewExport` (if beads enabled, create bead(s); otherwise write markdown)

## Behavior

- Visual line/block selections capture file path, line range, and code text.
- Comments are stored in memory for the current session.
- Export writes to `stdpath("cache")/review.nvim` by default.
- Beads integration uses the same export mode:
  - `single`: one bead for the whole review
  - `per_comment`: one bead per comment

## Beads configuration

```lua
require("review").setup({
  beads = {
    enabled = true,
    cmd = "bd",
    parent_from_branch = true,
    branch_pattern = "epic/([^/]+)",
    prompt_if_missing = true,
  },
})
```

If branch inference fails and prompting is enabled, you will be asked for a parent bead id.
