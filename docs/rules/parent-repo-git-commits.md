# Parent Repo Git Commit Rules

Use this rule when committing from the parent repository, especially when a
submodule such as `insights-share` has changes.

## Rule

Parent repo commits must stay scoped to parent-owned files and submodule
gitlink updates. If a submodule has file changes, commit and push those changes
inside the submodule first, then commit the parent repo submodule pointer.

## Required Order

1. Commit submodule file changes inside the submodule:
   `git -C <submodule> add ... && git -C <submodule> commit -m "..."`
2. Push the submodule commit:
   `git -C <submodule> push origin <branch>`
3. Commit the parent repo pointer update:
   `git add <submodule> && git commit -m "Update <submodule> submodule"`
4. Push the parent repo:
   `git push origin <branch>`

## Do Not Commit

- Submodule internal files directly from the parent repo.
- Local worktree artifacts such as `.claude/worktrees/`.
- OS metadata such as `.DS_Store`.
- Mixed commits that combine unrelated parent files and submodule pointer
  updates.

## Good Commit Shapes

- `Add project agent entrypoints`
- `Update insights-share submodule`
- `Ignore Claude worktree artifacts`
